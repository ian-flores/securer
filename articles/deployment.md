# Deployment and Sandboxing

## Sandbox overview

When `sandbox = TRUE`, the child process runs inside platform-native
OS-level restrictions. The sandbox prevents LLM-generated code from
accessing the filesystem, network, or other processes beyond what R
needs to function. Each platform uses a different mechanism, described
below.

## macOS (Seatbelt)

Uses `sandbox-exec` with a generated Seatbelt profile:

- File reads are allowed everywhere (R needs system libs and packages)
- File writes are blocked except to temp directories (`/tmp`,
  `/var/folders/`)
- All remote network access is blocked (TCP/UDP)
- Unix domain sockets are allowed (needed for IPC with the host)

``` r
session <- SecureSession$new(sandbox = TRUE)

# Computation works normally:
session$execute("1 + 1")
#> [1] 2

# Network access is blocked:
session$execute('readLines(url("http://example.com"))')
#> Error: Operation not permitted

# Writing outside temp is blocked:
session$execute('writeLines("test", "~/file.txt")')
#> Error: Operation not permitted

session$close()
```

## Linux (bubblewrap)

Uses `bwrap` with full namespace isolation (PID, network, user, mount,
UTS, IPC). System libraries and R are bind-mounted read-only. `/tmp` is
a clean writable tmpfs. Network access is blocked via the network
namespace.

Requires `bwrap` to be installed. On Debian/Ubuntu:
`apt install bubblewrap`. Falls back to unsandboxed execution with a
warning if not found.

## Windows

Provides environment-variable isolation only (clears `R_LIBS_USER`,
`R_ENVIRON_USER`, `R_PROFILE_USER`; redirects `HOME`/`TMPDIR` to a clean
temp directory). No filesystem or network restrictions. A warning is
issued.

## Resource limits

Apply `ulimit`-based caps to the child process. These work with or
without the sandbox:

``` r
execute_r("1 + 1", limits = list(cpu = 10, memory = 256 * 1024 * 1024))
```

Supported limits:

| Name     | Unit    | ulimit flag | Description           |
|----------|---------|-------------|-----------------------|
| `cpu`    | seconds | `-t`        | CPU time              |
| `memory` | bytes   | `-v`        | Virtual address space |
| `fsize`  | bytes   | `-f`        | Maximum file size     |
| `nproc`  | count   | `-u`        | Maximum processes     |
| `nofile` | count   | `-n`        | Maximum open files    |
| `stack`  | bytes   | `-s`        | Stack size            |

Default limits applied when `sandbox = TRUE`:

``` r
default_limits()
```

## Code pre-validation

[`validate_code()`](https://ian-flores.github.io/securer/reference/validate_code.md)
checks for syntax errors and dangerous patterns before sending code to
the child process:

``` r
# Valid code
validate_code("1 + 1")

# Syntax error
validate_code("if (TRUE {")

# Dangerous pattern (advisory warning, not a hard block)
validate_code("system('ls')")
```

## Sandbox verification

Before deploying, verify that sandbox tooling is available on your
target platform. Missing tools cause a fallback to unsandboxed execution
(or an error if `sandbox_strict = TRUE`):

``` r
if (Sys.info()[["sysname"]] == "Linux") stopifnot(nzchar(Sys.which("bwrap")))
if (Sys.info()[["sysname"]] == "Darwin") stopifnot(file.exists("/usr/bin/sandbox-exec"))
```

## Strict sandbox mode

By default, if sandbox tools are not available on the current platform,
securer falls back to unsandboxed execution with a warning. In
production, this fallback may be unacceptable — you want a hard error
instead of silently running without protection.

The `sandbox_strict` parameter controls this behavior. When `TRUE` and
`sandbox = TRUE`, the session will stop with an informative error if the
OS-level sandbox cannot be set up:

``` r
# Error if sandbox not available (recommended for production)
session <- SecureSession$new(sandbox = TRUE, sandbox_strict = TRUE)
```

When `FALSE` (the default), the existing behavior is preserved: a
warning is emitted and the session continues without OS-level
sandboxing. Resource limits, IPC validation, and environment
sanitization still apply.

## Architecture

    Host process                          Child R process (sandboxed)
    -----------                          ---------------------------
    SecureSession$new()
      |-- callr::r_session$new()  ------>  R starts inside sandbox
      |-- UDS server socket        <---->  UDS client connect
      |-- inject runtime code      ------>  .securer_call_tool() defined
      |-- inject tool wrappers     ------>  tool_name() wrappers defined

    $execute("tool_name('arg')")
      |                                     eval("tool_name('arg')")
      |                                       |-- serialize as JSON
      |   <---- {"tool":"tool_name",...} -----+
      |-- execute fn("arg")                   |   (child blocks)
      |-- write result JSON ---------------> |
      |                                       +-- return result
      |   <---- process complete -------------|
      +-- return final value

The sandbox wrapper is injected via
`callr::r_session_options(arch = ...)` and IPC uses a Unix domain socket
in `/tmp` (to stay under the ~104 char path limit on macOS). See
[`vignette("security-model")`](https://ian-flores.github.io/securer/articles/security-model.md)
for full details on the IPC protocol, trust boundaries, and defense
layers.

## Why not just callr or Docker?

**callr** gives you process isolation — the child runs in a separate R
process, so a crash or error does not bring down the host. But callr
provides no filesystem or network restrictions. The child can read your
SSH keys, make HTTP requests, and write anywhere on disk.

**Docker** provides full isolation (filesystem, network, PID, user
namespaces) but requires a running daemon, image management, and
container orchestration. It is heavier-weight, adds startup latency, and
does not include built-in tool-call IPC — you would need to build your
own protocol on top of stdin/stdout, HTTP, or sockets.

**securer** combines OS-native sandboxing (Seatbelt on macOS, bubblewrap
on Linux) with a purpose-built tool-call IPC protocol, resource limits,
environment sanitization, execution timeouts, and audit logging — all in
a single R package with no daemon and sub-second session startup. The
sandbox is lightweight because it uses the kernel’s own isolation
primitives rather than running a full container.

| Feature                 | callr | Docker | securer |
|-------------------------|-------|--------|---------|
| Process isolation       | Yes   | Yes    | Yes     |
| Filesystem restrictions | No    | Yes    | Yes     |
| Network restrictions    | No    | Yes    | Yes     |
| Tool-call IPC           | No    | No     | Yes     |
| Resource limits         | No    | Yes    | Yes     |
| Audit logging           | No    | No     | Yes     |
| No daemon required      | Yes   | No     | Yes     |
| Sub-second startup      | Yes   | No     | Yes     |
