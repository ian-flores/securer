# Security Model

This document describes the security architecture and threat model of
the securer package. It is intended for security auditors, deployers
evaluating risk, and contributors working on the sandboxing code.

## TL;DR

securer protects against LLM-generated R code with 10 defense layers:

- **OS sandbox** — Seatbelt (macOS) or bubblewrap (Linux) blocks
  filesystem writes and network access
- **Resource limits** — ulimit caps on CPU, memory, file size,
  processes, and open files
- **Execution timeouts** — wall-clock deadline kills runaway code;
  session auto-recovers
- **IPC authentication** — 32-character random token validates the child
  process identity
- **Message validation** — size limits, JSON structure checks, and tool
  name allowlist
- **Environment sanitization** — only allowlisted env vars inherited;
  API keys and credentials stripped
- **Argument validation** — type checks on both sides of the trust
  boundary
- **Code pre-validation** — syntax check and dangerous pattern warnings
  before execution
- **Socket permissions** — 0700 directory prevents other users from
  accessing the IPC socket
- **Runtime hardening** — locked bindings and sealed environments
  prevent internal tampering

For deployment details, see
[`vignette("deployment")`](https://ian-flores.github.io/securer/articles/deployment.md).
The rest of this document covers the full threat model.

## Threat model

### Attacker

The attacker is **LLM-generated R code** running inside the child
process. An LLM may produce code that is malicious by intent (prompt
injection) or by accident (hallucinated system calls, unintended side
effects). The code has full access to the R language within the child
process and can attempt arbitrary operations including file I/O, network
access, process execution, and resource exhaustion.

### What we are protecting

- **Host filesystem** – prevent reading sensitive files (SSH keys,
  credentials, application data) and writing to arbitrary locations
- **Network** – prevent the child from making HTTP requests,
  exfiltrating data, or connecting to internal services
- **Other processes** – prevent the child from signaling, debugging, or
  interfering with other processes on the host
- **Host resources** – prevent CPU exhaustion, memory exhaustion, fork
  bombs, and disk-filling attacks

### Trust boundaries

    +------------------------------------------+
    |  Host / parent process (TRUSTED)         |
    |  - Registers tools (fn runs here)        |
    |  - Controls session lifecycle            |
    |  - Reads/writes IPC socket               |
    +------------------+-----------------------+
                       |
                Unix domain socket
             (IPC boundary / trust boundary)
                       |
    +------------------+-----------------------+
    |  Child R process (UNTRUSTED)             |
    |  - Executes LLM-generated code           |
    |  - Can only call registered tools via    |
    |    .securer_call_tool() over IPC         |
    |  - Runs inside OS sandbox + ulimits      |
    +------------------------------------------+

The parent process is fully trusted. It registers tool functions,
manages the child process lifecycle, and executes tool calls with full
host privileges.

The child process is untrusted. All code evaluated in the child is
treated as potentially hostile. The IPC channel (Unix domain socket) is
the trust boundary. The child can only affect the host by sending
tool-call requests over this channel, which the parent validates before
executing.

## Defense layers

securer uses defense in depth. No single layer is sufficient; they are
designed to be redundant so that a bypass in one layer is caught by
another.

### Layer 1: OS-level sandbox

The outermost defense. Restricts what the child process can do at the
operating system level.

#### macOS: Seatbelt (`sandbox-exec`)

The child R process runs inside `sandbox-exec -f profile.sb`. The
profile is generated dynamically by
[`generate_seatbelt_profile()`](https://ian-flores.github.io/securer/reference/generate_seatbelt_profile.md)
with a **deny-default** policy:

``` r
# The generated profile starts with:
# (version 1)
# (deny default)
```

**Allowed operations:**

- **File reads**: R installation
  ([`R.home()`](https://rdrr.io/r/base/Rhome.html)), R library paths
  ([`.libPaths()`](https://rdrr.io/r/base/libPaths.html)), system
  libraries (`/usr`, `/Library/Frameworks`, `/System/Library`,
  `/opt/homebrew`), device nodes (`/dev`), specific `/etc` files
  (localtime, ssl certs, hosts), temp directories (`/tmp`,
  `/private/var/folders/`), and the sandbox profile itself
- **File writes**: only to the session-specific socket directory
  (`/tmp/securer_XXXXX/`), R’s per-user temp area
  (`/private/var/folders/...`), and specific device nodes (`/dev/null`,
  `/dev/tty`, `/dev/random`, `/dev/urandom`)
- **Network**: Unix domain sockets only (local IPC). All remote IP
  traffic (TCP/UDP) is explicitly denied
- **Process execution**: R binaries (`R.home()/bin/`), `/bin/sh`,
  `/bin/bash`, and a handful of POSIX utilities needed by R’s startup
  script (`sed`, `uname`, `grep`, `dirname`, `basename`, `rm`). Other
  interpreters (python, perl, ruby, node) are blocked
- **System**: Mach IPC, sysctl, signals, IOKit, POSIX IPC (required by R
  and macOS internals)

**Not allowed:**

- Writing to the user’s home directory
- Reading `~/.ssh`, `~/.aws`, `~/.config` (these paths are not under any
  allowed subpath, though note that broad `/usr` reads are allowed)
- Outbound HTTP/HTTPS connections
- Executing arbitrary binaries

The profile is written to a temp file and passed to `sandbox-exec -f`.
The wrapper script is injected via
`callr::r_session_options(arch = "/path/to/wrapper.sh")`, which callr
treats as a direct path to the R binary.

#### Linux: bubblewrap (`bwrap`)

The child runs inside `bwrap --unshare-all`, which creates isolated PID,
network, user, mount, UTS, and IPC namespaces:

``` r
# Key bwrap arguments:
# --unshare-all        isolate all namespaces
# --die-with-parent    kill child if parent dies
# --new-session        new session ID (prevents terminal hijacking)
# --ro-bind /usr /usr  read-only system libraries
# --ro-bind R.home()   read-only R installation
# --tmpfs /tmp         clean writable /tmp
# --bind socket_dir    writable socket directory (overlays /tmp)
# --proc /proc         minimal proc filesystem
# --dev /dev           minimal dev nodes
```

**Filesystem**: The root filesystem is not mounted. Only explicitly
listed paths are available. System libraries (`/usr`, `/lib`, `/lib64`,
`/bin`, `/sbin`), config files (`/etc/ld.so.cache`, `/etc/localtime`,
`/etc/ssl`, `/etc/R`), and the R installation are bind-mounted
read-only. R library paths outside `/usr` and
[`R.home()`](https://rdrr.io/r/base/Rhome.html) are also bind-mounted
read-only. `/tmp` is a clean `tmpfs`. The socket directory is
bind-mounted writable on top of `/tmp`.

**Network**: Completely isolated via `--unshare-net`. The child has no
network interfaces at all (not even loopback in some configurations).

**Process isolation**: Separate PID namespace. The child sees itself as
PID 1. Cannot see or signal host processes.

**HOME/TMPDIR**: Set to `/tmp` inside the namespace. `R_LIBS_USER` is
set empty.

#### Windows: environment isolation + Job Objects

Windows lacks a userspace sandboxing API equivalent to Seatbelt or
bubblewrap. securer provides two weaker mechanisms:

**Environment isolation**: The child gets a sanitized environment with
`HOME`, `TMPDIR`, `TMP`, and `TEMP` pointing to a private temp
directory, and `R_LIBS_USER` set to empty string. This prevents the
child from loading packages from the user’s personal library or writing
to the user’s home via `HOME`.

**Job Objects** (resource limits only): When resource limits are
specified, securer generates a PowerShell script that uses C# P/Invoke
to create a Windows Job Object and assign the child process to it.
Supported limits:

- `ProcessMemoryLimit` (from `memory` limit)
- `PerProcessUserTimeLimit` (from `cpu` limit, converted to 100ns units)
- `ActiveProcessLimit` (from `nproc` limit)

The Job Object also sets `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` so child
processes are terminated when the job handle closes.

Limits that have no Job Object equivalent (`fsize`, `nofile`, `stack`)
emit a warning and are skipped.

**No filesystem or network restrictions are applied on Windows.** The
child process can read and write anywhere the user account has access,
and can make network connections.

### Layer 2: Resource limits

Prevent resource exhaustion attacks. Applied via `ulimit` on Unix and
Job Objects on Windows.

``` r
library(securer)
# Default limits (applied automatically when sandbox = TRUE):
default_limits()
#> $cpu
#> [1] 60
#> 
#> $memory
#> [1] 536870912
#> 
#> $fsize
#> [1] 52428800
#> 
#> $nproc
#> [1] 50
#> 
#> $nofile
#> [1] 256
```

The wrapper script sets both soft and hard limits (`ulimit -S -H`)
before `exec`-ing R, so the child cannot raise them:

``` r
# Generated wrapper script (Unix):
# #!/bin/sh
# ulimit -S -H -t 60       # CPU seconds
# ulimit -S -H -v 524288   # virtual memory in KB
# ulimit -S -H -f 102400   # file size in 512-byte blocks
# ulimit -S -H -u 50       # max processes
# ulimit -S -H -n 256      # max open files
# exec /usr/bin/sandbox-exec -f /tmp/securer_XXX.sb /path/to/R "$@"
```

Resource limits can be used independently of the sandbox
(`sandbox = FALSE, limits = list(cpu = 30)`), in which case a minimal
wrapper script applies only the `ulimit` commands.

### Layer 3: Execution timeouts

Wall-clock deadline enforced in the parent’s event loop. Unlike
`ulimit -t` (which measures CPU time), this catches cases where the
child is blocked on I/O or sleeping:

``` r
session$execute("Sys.sleep(3600)", timeout = 10)
#> Error: Execution timed out after 10 seconds
```

On timeout:

1.  The child process is killed (`$kill()`)
2.  The IPC connection is cleaned up
3.  The socket and sandbox temp files are removed
4.  A new session is started automatically so the `SecureSession` object
    remains usable for subsequent calls

### Layer 4: IPC authentication

When the child process connects to the Unix domain socket, it must
present a 32-character random token as its first message. The parent
generates this token at session creation and passes it to the child via
the `SECURER_TOKEN` environment variable.

``` r
# Parent generates token:
private$ipc_token <- paste0(
  sample(c(letters, LETTERS, 0:9), 32, replace = TRUE),
  collapse = ""
)

# Child sends token as first message after connecting:
# processx::conn_write(conn, paste0(Sys.getenv("SECURER_TOKEN"), "\n"))

# Parent validates:
# if (!identical(auth_line, private$ipc_token))
#   stop("IPC authentication failed")
```

This prevents another process from connecting to the socket and
injecting tool calls. Combined with the 0700 directory permissions on
the socket directory, only the current user can access the socket.

### Layer 5: IPC message validation

Every message from the child is validated before processing:

1.  **Size limit**: Messages larger than 1 MB (configurable via
    `private$max_ipc_message_size`) are rejected before JSON parsing.
    This prevents memory exhaustion via a single oversized message.

2.  **JSON structure**: The parsed message must be a JSON object (list).
    The `type` field must be a scalar string.

3.  **Tool call validation**: For `type: "tool_call"` messages, the
    `tool` field must be a scalar string matching the regex
    `^[A-Za-z.][A-Za-z0-9_.]*$` (valid R identifier). The `args` field
    must be a list or null.

4.  **Tool name allowlist**: The tool name is looked up in the
    registered tool functions (`private$tool_fns`). Unknown tools return
    an error to the child.

5.  **Tool call rate limiting**: `$execute(code, max_tool_calls = N)`
    caps the number of tool calls per execution. Exceeding the limit
    raises an error and halts execution.

``` r
session$execute("while(TRUE) add(1, 1)", max_tool_calls = 100)
#> Error: Maximum tool calls (100) exceeded
```

### Layer 6: Environment sanitization

The child process inherits only an allowlisted set of environment
variables. All others are set to `NA` (which callr interprets as “remove
from child environment”):

``` r
# Allowlisted variables:
safe_vars <- c(
  "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE",
  "LC_MESSAGES", "LC_COLLATE", "LC_MONETARY", "LC_NUMERIC", "LC_TIME",
  "SHELL", "TMPDIR", "TZ", "TERM",
  "R_HOME", "R_LIBS_SITE",
  "R_PLATFORM", "R_ARCH"
)
```

`R_LIBS` and `R_LIBS_USER` are **intentionally excluded** from the
allowlist. These variables can point to attacker-controlled directories,
allowing malicious packages with `.onLoad` hooks to execute arbitrary
code in the child process, bypassing sandbox restrictions. The child
inherits only `R_HOME` and `R_LIBS_SITE` (system-level library paths
controlled by the R installation). `R_LIBS_USER` is explicitly set to
`""` to prevent user-level library injection on all platforms.

Everything not on this list is removed. This means:

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` – not inherited
- `GITHUB_TOKEN`, `OPENAI_API_KEY` – not inherited
- `DATABASE_URL`, `REDIS_URL` – not inherited
- Any custom `SECRET_*` or `API_*` variables – not inherited

Two securer-specific variables are added: `SECURER_SOCKET` (socket path)
and `SECURER_TOKEN` (authentication token).

### Layer 7: Tool argument validation

Two layers of argument validation, on both sides of the trust boundary:

**Parent-side** (in `run_with_tools()`): If argument metadata exists for
the called tool, any argument names not in the expected set are rejected
with an error sent back to the child. This prevents the child from
passing unexpected arguments to tool functions.

**Child-side** (in generated wrapper functions): When tool arguments
have type annotations (e.g., `args = list(x = "numeric")`), the
generated wrapper includes runtime type checks that run before the IPC
call:

``` r
# Generated wrapper for a tool with typed args:
add <- function(a, b) {
  if (!is.numeric(a)) stop("Tool 'add': argument 'a' must be numeric, got ",
                            class(a)[1], call. = FALSE)
  if (!is.numeric(b)) stop("Tool 'add': argument 'b' must be numeric, got ",
                            class(b)[1], call. = FALSE)
  .securer_call_tool("add", a = a, b = b)
}
```

### Layer 8: Code pre-validation

Before sending code to the child,
[`validate_code()`](https://ian-flores.github.io/securer/reference/validate_code.md)
performs two checks:

1.  **Syntax check**: `parse(text = code)` catches syntax errors
    immediately, avoiding a round-trip to the child process.

2.  **Dangerous pattern warnings**: Regex-based detection of calls to
    [`system()`](https://rdrr.io/r/base/system.html),
    [`system2()`](https://rdrr.io/r/base/system2.html),
    [`.Internal()`](https://rdrr.io/r/base/Internal.html),
    [`.Call()`](https://rdrr.io/r/base/CallExternal.html),
    [`dyn.load()`](https://rdrr.io/r/base/dynload.html),
    [`pipe()`](https://rdrr.io/r/base/connections.html),
    [`processx::run()`](http://processx.r-lib.org/reference/run.md),
    [`callr::r()`](https://callr.r-lib.org/reference/r.html),
    [`socketConnection()`](https://rdrr.io/r/base/connections.html),
    [`url()`](https://rdrr.io/r/base/connections.html), and
    [`do.call()`](https://rdrr.io/r/base/do.call.html).

**These warnings are advisory only.** They are not a security boundary.
The regex matching produces both false positives
(`"system() is a function"` in a string) and false negatives (indirect
invocation via `get("system")()`). The OS-level sandbox is the actual
enforcement layer.

### Layer 9: Socket directory permissions

The socket directory (`/tmp/securer_XXXXX/`) is created with mode
`0700`:

``` r
dir.create(private$socket_dir, mode = "0700")
```

Only the owning user can list, read, or write files in this directory.
This prevents other users on a shared system from connecting to the Unix
domain socket. Combined with the authentication token (Layer 4), a
connection from an unauthorized process is rejected even if it somehow
obtains a file descriptor to the socket.

### Layer 10: Child runtime hardening

The child runtime uses a **closure-based design** with a sealed inner
environment. `.securer_call_tool()` is defined via
[`local()`](https://rdrr.io/r/base/eval.html), which captures the UDS
connection in a private enclosing environment that is not directly
accessible from the global environment. The connection object is stored
in a sealed `.ipc_store` environment with a custom `$` method that
blocks direct access.

``` r
# In child_runtime_code():
# .securer_call_tool is defined as a closure via local({...})
# The UDS connection is captured in .ipc_store inside the closure:
.ipc_store <- new.env(parent = emptyenv())
.ipc_store$.c <- .conn
lockEnvironment(.ipc_store)
# ... the function is then locked in the global env:
lockBinding(".securer_call_tool", globalenv())
```

Additionally, [`unlockBinding()`](https://rdrr.io/r/base/bindenv.html)
is shadowed in the child’s global environment (and in the base namespace
where possible) to prevent child code from unlocking the binding.
[`getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html)
and
[`getNativeSymbolInfo()`](https://rdrr.io/r/base/getNativeSymbolInfo.html)
are also blocked via active bindings.

This means the child code cannot:

- Redefine `.securer_call_tool()` to bypass argument validation
- Access the raw UDS connection via
  `environment(.securer_call_tool)$conn`
- Use [`unlockBinding()`](https://rdrr.io/r/base/bindenv.html) to remove
  the lock (even via
  [`base::unlockBinding()`](https://rdrr.io/r/base/bindenv.html))

Tool wrapper functions (e.g., `add()`, `get_weather()`) injected by
[`generate_tool_wrappers()`](https://ian-flores.github.io/securer/reference/generate_tool_wrappers.md)
**are** locked. [`lockBinding()`](https://rdrr.io/r/base/bindenv.html)
is called for each wrapper after it is injected into the global
environment, so child code cannot redefine them either.

## What the sandbox prevents

Concrete outcomes for specific attack scenarios:

| Attack                      | Linux (bwrap)                                                                                                     | macOS (Seatbelt)                                                                                                                                                                                                                                                                                                           | Windows                                                             |
|-----------------------------|-------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Read `/etc/passwd`          | Blocked – not mounted                                                                                             | Allowed – broad `/usr` read includes `/etc` indirectly, but specific `/etc` reads are allowlisted; `/etc/passwd` is not on the allowlist, so it depends on `file-read-metadata` vs `file-read*` rules. In practice: **readable** (metadata allowed globally, and `/etc/passwd` may be accessible via system library paths) | N/A (no `/etc/passwd`)                                              |
| Read `~/.ssh/id_rsa`        | Blocked – home dir not mounted                                                                                    | Blocked – home dir not in any allowed read subpath                                                                                                                                                                                                                                                                         | **Not blocked**                                                     |
| Write `~/evil.txt`          | Blocked – root is read-only, home not mounted                                                                     | Blocked – writes only allowed to temp dirs                                                                                                                                                                                                                                                                                 | **Not blocked**                                                     |
| Outbound HTTP request       | Blocked – no network namespace                                                                                    | Blocked – `(deny network* (remote ip))`                                                                                                                                                                                                                                                                                    | **Not blocked**                                                     |
| Fork bomb (`repeat fork()`) | Limited – `ulimit -u 50` caps processes                                                                           | Limited – `ulimit -u 50` caps processes                                                                                                                                                                                                                                                                                    | Limited – Job Object `ActiveProcessLimit`                           |
| Allocate 10 GB RAM          | Limited – `ulimit -v 512MB`                                                                                       | Limited – `ulimit -v 512MB`                                                                                                                                                                                                                                                                                                | Limited – Job Object `ProcessMemoryLimit`                           |
| Infinite CPU loop           | Limited – `ulimit -t 60` + wall-clock timeout                                                                     | Limited – `ulimit -t 60` + wall-clock timeout                                                                                                                                                                                                                                                                              | Limited – Job Object `PerProcessUserTimeLimit` + wall-clock timeout |
| Execute `/usr/bin/python`   | Blocked – not bind-mounted under allowed paths (only `/usr` is mounted, but process exec is limited by namespace) | Blocked – `process-exec` restricted to R binaries and specific POSIX utilities                                                                                                                                                                                                                                             | **Not blocked**                                                     |
| Write 1 GB file to `/tmp`   | Limited – `ulimit -f 50MB`                                                                                        | Limited – `ulimit -f 50MB`                                                                                                                                                                                                                                                                                                 | Not limited (no `fsize` on Windows)                                 |
| Open 1000 files             | Limited – `ulimit -n 256`                                                                                         | Limited – `ulimit -n 256`                                                                                                                                                                                                                                                                                                  | Not limited (no `nofile` on Windows)                                |

## Known limitations

This section documents gaps in the security model. These are design
trade-offs, not bugs, but deployers should understand them.

### Windows has no filesystem or network restrictions

See Layer 1 (Windows) above. **Mitigation**: Run the host process inside
a Docker container or Windows Sandbox.

### macOS Seatbelt allows broad file reads

`file-read*` is allowed on `/usr`, `/Library/Frameworks`,
`/System/Library`, `/opt/homebrew`, `/bin`, and `/dev` (R needs system
libraries at runtime). `file-read-metadata` is allowed globally (R needs
`stat()`), so the child can discover file existence and size even where
it cannot read contents. The user’s home directory is not readable.

**Mitigation**: Don’t store sensitive data in system-wide readable
locations. Environment sanitization (Layer 6) protects credentials in
env vars.

### `sandbox-exec` is deprecated by Apple

Apple has deprecated `sandbox-exec` and the Seatbelt profile language.
As of macOS 15 (Sequoia), it still functions and is used by Apple’s own
tools, but it could be removed in a future release with no public
replacement for third-party use.

**Mitigation**: Monitor macOS release notes. If `sandbox-exec` is
removed, the fallback path emits a warning and runs without OS-level
sandboxing (resource limits and IPC validation still apply).

### ulimit is per-process, not per-session

`ulimit` values apply to each individual process. A child that forks
inherits the limits, but the fork itself counts as one process against
the `nproc` limit. The `nproc` limit is also per-user, not per-session,
so other processes by the same user count against it.

### IPC channel is not encrypted

Communication between parent and child uses plaintext JSON over the Unix
domain socket. The socket is protected by filesystem permissions (0700
directory) and the authentication token, but the data is not encrypted
in transit. On a compromised host where an attacker has the same UID,
they could potentially read IPC traffic.

**Mitigation**: The socket directory has 0700 permissions and a random
name. The authentication token prevents unauthorized connections. If the
host is compromised at the UID level, the attacker already has access to
everything the session can access.

### Code pre-validation is advisory only

See Layer 8 above. Regex matching has both false positives and false
negatives. The OS sandbox is the actual enforcement layer.

### Tool wrapper functions are locked but `.securer_call_tool()` remains accessible

Tool wrapper functions are now locked via
[`lockBinding()`](https://rdrr.io/r/base/bindenv.html). However, the
child can still call `.securer_call_tool()` directly to make arbitrary
tool calls (subject to parent-side tool name allowlist and argument
validation). Locking the wrappers prevents accidental redefinition but
does not restrict tool access beyond what the parent already enforces.

### Session pooling multiplies the attack surface

`SecureSessionPool$new(size = 4)` creates 4 independent child processes,
each with its own UDS, sandbox config, and resource limits. A
vulnerability in the sandbox affects all pool members. Dead sessions are
auto-restarted on acquire, which means a child that crashes (e.g., from
hitting a resource limit) gets replaced transparently.

### Fallback to unsandboxed execution

When `sandbox-exec` (macOS) or `bwrap` (Linux) is not found, securer
falls back to unsandboxed execution with a warning. Resource limits, IPC
validation, and environment sanitization still apply.

### The child can consume resources within limits

Resource limits bound but do not prevent resource use. The defaults (60s
CPU, 512 MB memory, 50 MB file, 50 processes) may be too generous for
your use case. See “Tighten resource limits” in Recommendations below.

### `lockBinding` bypass routes are shadowed but not eliminated

[`unlockBinding()`](https://rdrr.io/r/base/bindenv.html) is shadowed in
both the global environment and (where possible) the base namespace.
[`getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html)
and
[`getNativeSymbolInfo()`](https://rdrr.io/r/base/getNativeSymbolInfo.html)
are blocked via active bindings. However, a sufficiently determined
attacker may find other reflection paths to recover the original
[`base::unlockBinding`](https://rdrr.io/r/base/bindenv.html).

The practical impact is low: even if a child redefines
`.securer_call_tool()`, it can only change how it constructs IPC
messages. The parent validates all messages independently
(defense-in-depth).

## IPC protocol details

### Transport

- **Socket type**: Unix domain socket (AF_UNIX, SOCK_STREAM)
- **Socket path**: `/tmp/securer_XXXXX/ipc.sock` (Unix) or
  `%TEMP%\securer_XXXXX\ipc.sock` (Windows)
- **Path length**: Uses `/tmp` directly to stay under the ~104 character
  limit for Unix domain socket paths on macOS
  ([`tempdir()`](https://rdrr.io/r/base/tempfile.html) can be deeply
  nested during `R CMD check`)
- **Direction**: Bidirectional. Parent creates server, child connects.
- **Library**:
  [`processx::conn_create_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md)
  /
  [`processx::conn_connect_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md)

### Connection lifecycle

1.  Parent creates server socket at `/tmp/securer_XXXXX/ipc.sock`
2.  Parent starts child process (via `callr::r_session$new()`)
3.  Child runtime code connects to the socket path from `SECURER_SOCKET`
    env var
4.  Parent accepts the connection
    ([`processx::conn_accept_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md)
    – transitions the server connection in-place, does not return a new
    object)
5.  Child sends the authentication token (from `SECURER_TOKEN` env var)
6.  Parent validates the token; rejects on mismatch

### Message format

Newline-delimited JSON. Each message is a single line terminated by
`\n`.

**Tool call (child to parent):**

``` json
{"type":"tool_call","tool":"add","args":{"a":1,"b":2}}
```

**Tool response (parent to child):**

``` json
{"value":3}
```

**Tool error (parent to child):**

``` json
{"error":"Unknown tool: nonexistent"}
```

### Flow

The protocol is synchronous. The child blocks on a socket read after
sending a tool call. The parent executes the tool function with full
host privileges, then writes the result back. The child resumes with the
return value.

There is no multiplexing or out-of-order execution. Each tool call is a
synchronous request/response pair.

### Timeout behavior

The parent’s event loop polls the UDS and the child process in a loop
with 200ms intervals. If a wall-clock deadline is set, the loop checks
remaining time each iteration. When the deadline expires, the child is
killed, the IPC connection is torn down, and a new session is started.

## Recommendations for deployers

### Always use `sandbox = TRUE` in production

Without the sandbox, the child process has the same privileges as the
parent.

### Tighten resource limits for your workload

The defaults (60s CPU, 512 MB memory) are intentionally generous.
Tighten them:

``` r
session <- SecureSession$new(
  sandbox = TRUE,
  limits = list(cpu = 10, memory = 128 * 1024 * 1024, nproc = 10)
)
```

### Use execution timeouts and tool call caps

``` r
session$execute(llm_code, timeout = 30, max_tool_calls = 50)
```

Timeouts catch cases where `ulimit -t` does not apply (I/O blocking,
sleeping). Tool call caps prevent tight-loop abuse.

### Review tool functions carefully

Tool functions run on the host with full privileges. Apply least
privilege — use parameterized queries and validate inputs:

``` r
securer_tool("get_user", "Look up user by ID",
  fn = function(user_id) {
    stopifnot(is.numeric(user_id), user_id > 0)
    DBI::dbGetQuery(conn, "SELECT name, email FROM users WHERE id = ?",
                    params = list(user_id))
  },
  args = list(user_id = "numeric"))
```

### Enable audit logging

``` r
session <- SecureSession$new(sandbox = TRUE, audit_log = "/var/log/securer/audit.jsonl")
```

Events logged: `session_start`, `session_close`, `execute_start`,
`execute_complete`, `execute_error`, `execute_timeout`, `tool_call`,
`tool_result`.

### On Windows, use container isolation

Run the host process inside Docker or WSL2 with bwrap to get the
filesystem and network restrictions the Windows sandbox lacks.
