# Security model

This vignette is for people who need to judge whether securer is safe
enough for them: security reviewers, people deploying it, and anyone
changing the sandbox code. It covers what securer protects against, how,
and where the gaps are.

## Summary

securer has ten separate protections against R code written by an LLM:

| Protection | What it does |
|----|----|
| OS sandbox | Seatbelt on macOS and bubblewrap on Linux block file writes and network access |
| Resource limits | `ulimit` caps CPU time, memory, file size, processes, and open files |
| Timeouts | A wall-clock deadline kills code that runs too long, and the session restarts |
| Socket authentication | The child must send a random token before the parent accepts anything from it |
| Message checks | Messages from the child are checked for size and shape, and tool names must be registered |
| Clean environment | The child gets only a short list of safe environment variables, so API keys and passwords don’t reach it |
| Argument checks | Tool arguments are checked in the child and again in the parent |
| Syntax check | Code that doesn’t parse never reaches the child, and risky calls get a warning |
| Socket permissions | The socket’s directory is `0700`, so other users can’t reach it |
| Locked runtime | The child’s internal functions are locked so code can’t replace them |

[`vignette("deployment")`](https://ian-flores.github.io/securer/articles/deployment.md)
covers setup. The rest of this page goes through each protection and its
limits.

## Threat model

### The attacker

The attacker is the R code the LLM writes, running in the child process.
The code might be hostile because someone slipped instructions into the
prompt, or harmful by accident because the model got something wrong.
Either way, it can use all of R inside the child. It can try to read and
write files, open network connections, start other programs, and use up
memory or CPU.

### What’s being protected

- Your files. The code shouldn’t read SSH keys, credentials, or
  application data, or write anywhere it likes.
- The network. The code shouldn’t make HTTP requests, send data out, or
  reach internal services.
- Other processes. The code shouldn’t be able to signal or interfere
  with them.
- The machine itself. The code shouldn’t be able to use up all the CPU,
  memory, process slots, or disk.

### Who trusts whom

![](data:image/svg+xml;base64,PHN2ZyByb2xlPSJpbWciIGFyaWEtbGFiZWw9IlRoZSBob3N0IHNlc3Npb24gaXMgdHJ1c3RlZDsgdGhlIHNhbmRib3hlZCBjaGlsZCBpcyBub3Q7IHRoZSBzb2NrZXQgYmV0d2VlbiB0aGVtIGlzIHRoZSBib3VuZGFyeSIgdmlld2JveD0iMCAwIDkwMCAzOTAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGRlZnM+PG1hcmtlciBpZD0idHItYXJyb3ciIHZpZXdib3g9IjAgMCAxMCAxMCIgcmVmeD0iOSIgcmVmeT0iNSIgbWFya2Vyd2lkdGg9IjciIG1hcmtlcmhlaWdodD0iNyIgb3JpZW50PSJhdXRvLXN0YXJ0LXJldmVyc2UiPjxwYXRoIGQ9Ik0xIDFMOSA1TDEgOSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjMmIxZjEyIiBzdHJva2Utd2lkdGg9IjEiIC8+PC9tYXJrZXI+PHBhdHRlcm4gaWQ9InRyLWhhdGNoIiB3aWR0aD0iNiIgaGVpZ2h0PSI2IiBwYXR0ZXJudW5pdHM9InVzZXJTcGFjZU9uVXNlIiBwYXR0ZXJudHJhbnNmb3JtPSJyb3RhdGUoNDUpIj48bGluZSB4MT0iMCIgeTE9IjAiIHgyPSIwIiB5Mj0iNiIgc3Ryb2tlPSIjYmY1YTM2IiBzdHJva2Utd2lkdGg9IjAuNiIgb3BhY2l0eT0iMC41NSI+PC9saW5lPjwvcGF0dGVybj48L2RlZnM+PHJlY3QgeD0iNDAiIHk9IjIwIiB3aWR0aD0iODIwIiBoZWlnaHQ9IjExOCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjMmIxZjEyIiBzdHJva2Utd2lkdGg9IjAuNzUiIC8+PHRleHQgeD0iNTYiIHk9IjQyIiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iMTAuNSIgZmlsbD0iIzJiMWYxMiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXdlaWdodD0iNzAwIiBsZXR0ZXItc3BhY2luZz0iMS4yIj5IT1NUIFIgU0VTU0lPTjwvdGV4dD48dGV4dCB4PSI4NDQiIHk9IjQyIiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iOSIgZmlsbD0iIzZiNTYzOCIgdGV4dC1hbmNob3I9ImVuZCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjIiPlRSVVNURUQ8L3RleHQ+PHRleHQgeD0iNTYiIHk9IjcwIiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iOS41IiBmaWxsPSIjNmI1NjM4IiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtd2VpZ2h0PSI0MDAiIGxldHRlci1zcGFjaW5nPSIwLjMiPuKAlCAgcmVnaXN0ZXJzIHRoZSB0b29scywgYW5kIHRoZWlyIGZ1bmN0aW9ucyBydW4gaGVyZTwvdGV4dD48dGV4dCB4PSI1NiIgeT0iOTAiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSI5LjUiIGZpbGw9IiM2YjU2MzgiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuMyI+4oCUICBzdGFydHMgYW5kIHN0b3BzIHRoZSBjaGlsZDwvdGV4dD48dGV4dCB4PSI1NiIgeT0iMTEwIiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iOS41IiBmaWxsPSIjNmI1NjM4IiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtd2VpZ2h0PSI0MDAiIGxldHRlci1zcGFjaW5nPSIwLjMiPuKAlCAgcmVhZHMgYW5kIGNoZWNrcyBldmVyeSBtZXNzYWdlIG9uIHRoZSBzb2NrZXQ8L3RleHQ+PHBhdGggZD0iTTIwIDE4Nkg4ODBNMjAgMTkwSDg4MCIgc3Ryb2tlPSIjYmY1YTM2IiBzdHJva2Utd2lkdGg9IjAuNzUiIC8+PHRleHQgeD0iNDAiIHk9IjE3OCIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkiIGZpbGw9IiNiZjVhMzYiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjIiPlRSVVNUIEJPVU5EQVJZIMK3IFVOSVggRE9NQUlOIFNPQ0tFVDwvdGV4dD48cGF0aCBkPSJNNDUwIDE0MFYyMzIiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzJiMWYxMiIgc3Ryb2tlLXdpZHRoPSIwLjc1IiBtYXJrZXItc3RhcnQ9InVybCgjdHItYXJyb3cpIiBtYXJrZXItZW5kPSJ1cmwoI3RyLWFycm93KSIgLz48dGV4dCB4PSI0NjIiIHk9IjIxNCIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkiIGZpbGw9IiM2YjU2MzgiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuMyI+dG9vbCBjYWxscyBvbmx5PC90ZXh0PjxyZWN0IHg9IjQwIiB5PSIyMzYiIHdpZHRoPSI4MjAiIGhlaWdodD0iMTM4IiBmaWxsPSJ1cmwoI3RyLWhhdGNoKSIgb3BhY2l0eT0iMC4zNSIgLz48cmVjdCB4PSI0MCIgeT0iMjM2IiB3aWR0aD0iODIwIiBoZWlnaHQ9IjEzOCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjYmY1YTM2IiBzdHJva2Utd2lkdGg9IjAuNzUiIC8+PHRleHQgeD0iNTYiIHk9IjI1OCIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjEwLjUiIGZpbGw9IiNiZjVhMzYiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjcwMCIgbGV0dGVyLXNwYWNpbmc9IjEuMiI+Q0hJTEQgUiBQUk9DRVNTPC90ZXh0Pjx0ZXh0IHg9Ijg0NCIgeT0iMjU4IiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iOSIgZmlsbD0iI2JmNWEzNiIgdGV4dC1hbmNob3I9ImVuZCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjIiPlVOVFJVU1RFRDwvdGV4dD48dGV4dCB4PSI1NiIgeT0iMjg2IiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iOS41IiBmaWxsPSIjMmIxZjEyIiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtd2VpZ2h0PSI0MDAiIGxldHRlci1zcGFjaW5nPSIwLjMiPuKAlCAgcnVucyB0aGUgY29kZSB0aGUgbW9kZWwgd3JvdGU8L3RleHQ+PHRleHQgeD0iNTYiIHk9IjMwNiIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkuNSIgZmlsbD0iIzJiMWYxMiIgdGV4dC1hbmNob3I9InN0YXJ0IiBmb250LXdlaWdodD0iNDAwIiBsZXR0ZXItc3BhY2luZz0iMC4zIj7igJQgIGNhbiBvbmx5IHJlYWNoIHlvdSB0aHJvdWdoIC5zZWN1cmVyX2NhbGxfdG9vbCgpPC90ZXh0Pjx0ZXh0IHg9IjU2IiB5PSIzMjYiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSI5LjUiIGZpbGw9IiMyYjFmMTIiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuMyI+4oCUICBydW5zIGluc2lkZSB0aGUgT1Mgc2FuZGJveCwgd2l0aCByZXNvdXJjZSBsaW1pdHM8L3RleHQ+PC9zdmc+)

Fig. 1 · Who trusts whom

The parent process is trusted. It registers the tools, starts and stops
the child, and runs tool calls with your full permissions.

The child is not trusted. securer treats everything that runs there as
possibly hostile. The socket between them is the boundary. The only way
the child can affect your session is by sending tool calls over it, and
the parent checks every one before running it.

## The protections

Several of these overlap on purpose, so getting past one doesn’t give
the code everything.

### 1. OS sandbox

This is the outer wall. The operating system limits what the child
process can do.

#### macOS: Seatbelt (`sandbox-exec`)

The child runs under `sandbox-exec -f profile.sb`.
[`generate_seatbelt_profile()`](https://ian-flores.github.io/securer/reference/generate_seatbelt_profile.md)
writes the profile for each session. It denies everything by default:

``` r

# The generated profile starts with:
# (version 1)
# (deny default)
```

and then allows only these:

|  | Allowed |
|----|----|
| File reads | R itself ([`R.home()`](https://rdrr.io/r/base/Rhome.html)), your library paths ([`.libPaths()`](https://rdrr.io/r/base/libPaths.html)), system libraries (`/usr/lib`, `/usr/share`, `/Library/Frameworks`, `/System/Library`, parts of `/opt/homebrew`, and others), a few device nodes, a few `/etc` files (time zone, SSL certificates, `hosts`), temp directories, and the profile itself |
| File writes | The session’s socket directory (`/tmp/securer_XXXXX/`), R’s per-user temp area (`/private/var/folders/...`), and a few device nodes (`/dev/null`, `/dev/tty`, `/dev/random`, `/dev/urandom`) |
| Network | Unix domain sockets only. All TCP and UDP traffic is denied |
| Running programs | R’s own binaries (`R.home()/bin/`), `/bin/sh`, and the few utilities R’s startup script calls (`sed`, `uname`, `grep`, `dirname`, `basename`, `rm`). Other interpreters, such as Python, Perl, Ruby, and Node, are blocked |
| System | Mach IPC, sysctl, signals, IOKit, and POSIX IPC, which R and macOS need |

So the child can’t write to your home directory, read `~/.ssh`,
`~/.aws`, or `~/.config`, make HTTP or HTTPS connections, or run other
programs.

securer writes the profile to a temp file and starts R through a wrapper
script that calls `sandbox-exec -f`. It hands the wrapper to callr as
`callr::r_session_options(arch = "/path/to/wrapper.sh")`, and callr
treats it as the path to the R binary.

#### Linux: bubblewrap (`bwrap`)

The child runs under `bwrap --unshare-all`, so it gets its own process,
network, user, mount, host name, and IPC namespaces. It also loses all
Linux capabilities (`--cap-drop ALL`).

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

Filesystem. Nothing is mounted unless it’s listed. System directories
(`/usr`, `/lib`, `/lib64`, `/bin`, `/sbin`), a few config files
(`/etc/ld.so.cache`, `/etc/localtime`, `/etc/ssl`, `/etc/R`), and R
itself are mounted read-only. So are any R library paths outside `/usr`
and [`R.home()`](https://rdrr.io/r/base/Rhome.html). `/tmp` is an empty
in-memory directory, with the socket directory mounted writable on top.
A few files under `/proc/self` that would expose environment variables,
memory layout, or open file descriptors are hidden behind empty mounts.

Network. The child has its own network namespace with no interfaces, so
it has no network at all. Depending on the setup, it may not even have
loopback.

Processes. The child has its own process namespace and sees itself as
process 1. It can’t see or signal anything on the host.

`HOME` and `TMPDIR` are `/tmp` inside the sandbox, and `R_LIBS_USER` is
empty.

#### Windows: clean environment and Job Objects

Windows has nothing like Seatbelt or bubblewrap that a normal program
can use. securer does two weaker things instead.

It cleans the environment. `HOME`, `TMPDIR`, `TMP`, and `TEMP` point to
a private temp directory, and `R_LIBS_USER` is empty. The child can’t
load packages from your personal library or write to your home directory
through `HOME`.

It sets resource limits with a Job Object, if you ask for limits.
securer writes a PowerShell script that uses C# P/Invoke to create the
Job Object and put the child process in it. Three limits are supported:

- `ProcessMemoryLimit`, from the `memory` limit
- `PerProcessUserTimeLimit`, from the `cpu` limit (converted to 100 ns
  units)
- `ActiveProcessLimit`, from the `nproc` limit

The Job Object also sets `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so the
child’s processes end when the job handle closes. The limits that have
no Job Object version (`fsize`, `nofile`, `stack`) are skipped with a
warning.

That’s all. On Windows the child can read and write anything your
account can, and it can use the network.

### 2. Resource limits

Limits stop code from using up the machine. securer sets them with
`ulimit` on macOS and Linux and with Job Objects on Windows.

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

The wrapper script sets both the soft and hard limit (`ulimit -S -H`)
before it starts R, so the child can’t raise them again:

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

You can use limits without the sandbox
(`sandbox = FALSE, limits = list(cpu = 30)`). The wrapper script then
only runs the `ulimit` commands.

### 3. Timeouts

The parent’s event loop enforces a wall-clock deadline. `ulimit -t` only
counts CPU time, so it doesn’t catch code that’s waiting on I/O or
sleeping. The timeout does:

``` r

session$execute("Sys.sleep(3600)", timeout = 10)
#> Error: Execution timed out after 10 seconds
```

When the deadline passes, securer:

1.  Kills the child process (`$kill()`).
2.  Closes the socket connection.
3.  Removes the socket and the sandbox’s temp files.
4.  Starts a new child, so you can keep using the same `SecureSession`.

### 4. Socket authentication

When the child connects to the socket, its first message has to be a
random token. The parent makes the token when the session starts and
passes it to the child in the `SECURER_TOKEN` environment variable. On
macOS and Linux it’s 32 bytes from `/dev/urandom`, written as 64 hex
characters. Where `/dev/urandom` doesn’t exist, it’s 32 random letters
and digits.

``` r

# Parent generates the token from /dev/urandom:
raw_bytes <- readBin(file("/dev/urandom", open = "rb"), "raw", 32)
private$ipc_token <- paste0(sprintf("%02x", as.integer(raw_bytes)), collapse = "")
# (Without /dev/urandom it falls back to
#  sample(c(letters, LETTERS, 0:9), 32, replace = TRUE).)

# Child sends token as first message after connecting:
# processx::conn_write(conn, paste0(Sys.getenv("SECURER_TOKEN"), "\n"))

# Parent validates:
# if (!identical(auth_line, private$ipc_token))
#   stop("IPC authentication failed")
```

Another process can’t connect to the socket and send its own tool calls,
because it doesn’t have the token. The socket directory’s `0700`
permissions (section 9) mean only your user can reach the socket in the
first place.

### 5. Message checks

The parent checks every message from the child before acting on it:

1.  Size. Messages over 1 MB (`private$max_ipc_message_size`) are
    rejected before they’re parsed, so one huge message can’t use up
    memory.
2.  Shape. The message has to be a JSON object, and its `type` field has
    to be a single string.
3.  Tool calls. For a `"tool_call"` message, `tool` has to be a single
    string that looks like an R name (`^[A-Za-z.][A-Za-z0-9_.]*$`), and
    `args` has to be a list or null.
4.  Registered tools only. The tool name has to be one you registered
    (`private$tool_fns`). Anything else gets an error back.
5.  Call limit. `$execute(code, max_tool_calls = N)` caps the number of
    tool calls in one run. Going over stops the run with an error.

``` r

session$execute("while(TRUE) add(1, 1)", max_tool_calls = 100)
#> Error: Maximum tool calls (100) exceeded
```

### 6. Clean environment

The child gets only the environment variables on a short list. securer
sets every other variable to `NA`, which tells callr to leave it out:

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

`R_LIBS` and `R_LIBS_USER` are left off the list on purpose. They can
point at a directory an attacker controls, and a package there could run
code in its `.onLoad()` hook before the sandbox has any say. The child
only gets `R_HOME` and `R_LIBS_SITE`, which point at libraries that
belong to the R installation. `R_LIBS_USER` is set to `""` on every
platform.

Anything not on the list is gone, including `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `GITHUB_TOKEN`, `OPENAI_API_KEY`,
`DATABASE_URL`, `REDIS_URL`, and any `SECRET_*` or `API_*` variables of
your own.

securer adds two variables of its own: `SECURER_SOCKET`, the socket
path, and `SECURER_TOKEN`, the token from section 4.

### 7. Argument checks

Tool arguments are checked on both sides of the socket.

In the parent (`run_with_tools()`): if the tool declares its arguments,
any argument name the tool doesn’t expect is rejected, and the child
gets an error back. The child can’t slip extra arguments into your
functions.

In the child: if the tool’s arguments have types
(`args = list(x = "numeric")`), the wrapper function securer generates
checks them before the call goes over the socket:

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

### 8. Syntax check

Before code goes to the child,
[`validate_code()`](https://ian-flores.github.io/securer/reference/validate_code.md)
does two things:

1.  It parses the code with `parse(text = code)`, so syntax errors show
    up straight away instead of after a trip to the child.
2.  It warns about calls that look risky:
    [`system()`](https://rdrr.io/r/base/system.html),
    [`system2()`](https://rdrr.io/r/base/system2.html), `shell()`,
    [`.Internal()`](https://rdrr.io/r/base/Internal.html),
    [`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html),
    [`.Call()`](https://rdrr.io/r/base/CallExternal.html),
    [`.C()`](https://rdrr.io/r/base/Foreign.html),
    [`.Fortran()`](https://rdrr.io/r/base/Foreign.html),
    [`.External()`](https://rdrr.io/r/base/CallExternal.html),
    [`dyn.load()`](https://rdrr.io/r/base/dynload.html),
    [`pipe()`](https://rdrr.io/r/base/connections.html),
    [`processx::run()`](http://processx.r-lib.org/reference/run.md),
    [`callr::r()`](https://callr.r-lib.org/reference/r.html),
    [`socketConnection()`](https://rdrr.io/r/base/connections.html),
    [`url()`](https://rdrr.io/r/base/connections.html), and
    [`do.call()`](https://rdrr.io/r/base/do.call.html).

The warnings are only advice. They aren’t a security boundary. The
checks are regular expressions, so they flag harmless text
(`"system() is a function"` inside a string) and miss indirect calls
(`get("system")()`). The OS sandbox is what actually stops these calls.

### 9. Socket permissions

The socket directory (`/tmp/securer_XXXXX/`) is created with mode
`0700`:

``` r

dir.create(private$socket_dir, mode = "0700")
```

Only the user who owns it can list, read, or write files there, so other
users on a shared machine can’t connect to the socket. And if some other
process did get a connection, it still wouldn’t have the token from
section 4.

### 10. Locked runtime

The function the child uses to make tool calls, `.securer_call_tool()`,
is built with [`local()`](https://rdrr.io/r/base/eval.html). The socket
connection lives inside it, in a private `.ipc_store` environment that’s
locked and has its own `$` method that refuses access. Code in the
child’s global environment can’t get at it directly.

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

securer also replaces
[`unlockBinding()`](https://rdrr.io/r/base/bindenv.html) in the child’s
global environment, and in the base namespace where it can, so child
code can’t undo the locks.
[`getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html)
and
[`getNativeSymbolInfo()`](https://rdrr.io/r/base/getNativeSymbolInfo.html)
are blocked with active bindings.

As a result, child code can’t:

- redefine `.securer_call_tool()` to skip the argument checks,
- reach the raw socket with `environment(.securer_call_tool)$conn`, or
- remove the lock with
  [`unlockBinding()`](https://rdrr.io/r/base/bindenv.html), even as
  [`base::unlockBinding()`](https://rdrr.io/r/base/bindenv.html).

The tool wrappers that
[`generate_tool_wrappers()`](https://ian-flores.github.io/securer/reference/generate_tool_wrappers.md)
creates, such as `add()` or `get_weather()`, are locked too. securer
calls [`lockBinding()`](https://rdrr.io/r/base/bindenv.html) on each one
after defining it, so child code can’t redefine them.

## What the sandbox stops

What happens with some specific attacks:

| Attack | Linux (bwrap) | macOS (Seatbelt) | Windows |
|----|----|----|----|
| Read `/etc/passwd` | Blocked: not mounted | Blocked: not on the read list, though its size and dates are visible because metadata reads are allowed everywhere | N/A (no `/etc/passwd`) |
| Read `~/.ssh/id_rsa` | Blocked: home directory not mounted | Blocked: home directory not on the read list | **Not blocked** |
| Write `~/evil.txt` | Blocked: filesystem is read-only and home isn’t mounted | Blocked: writes only allowed in temp directories | **Not blocked** |
| Outbound HTTP request | Blocked: empty network namespace | Blocked: `(deny network* (remote ip))` | **Not blocked** |
| Fork bomb (`repeat fork()`) | Limited: `ulimit -u 50` | Limited: `ulimit -u 50` | Limited: Job Object `ActiveProcessLimit` |
| Allocate 10 GB of memory | Limited: `ulimit -v` 512 MB | Limited: `ulimit -v` 512 MB | Limited: Job Object `ProcessMemoryLimit` |
| Infinite CPU loop | Limited: `ulimit -t 60` and the timeout | Limited: `ulimit -t 60` and the timeout | Limited: Job Object `PerProcessUserTimeLimit` and the timeout |
| Run `/usr/bin/python` | Not blocked: `/usr` is mounted, so an installed interpreter can run, but it’s inside the same sandbox with no network and no writable home | Blocked: only R and a few utilities can run | **Not blocked** |
| Write a 1 GB file to `/tmp` | Limited: `ulimit -f` 50 MB | Limited: `ulimit -f` 50 MB | Not limited (no `fsize` on Windows) |
| Open 1000 files | Limited: `ulimit -n 256` | Limited: `ulimit -n 256` | Not limited (no `nofile` on Windows) |

The limits in this table are the defaults from
[`default_limits()`](https://ian-flores.github.io/securer/reference/default_limits.md).

## Known limitations

These are gaps you should know about before you deploy. Most of them are
trade-offs, not bugs.

### Windows has no file or network restrictions

See the Windows section above. To get those restrictions, use the
docker-spawn backend (`SECURER_SANDBOX_MODE=docker-spawn`), or run the
whole R process in a Linux container, WSL2 with bubblewrap, or Windows
Sandbox.

### Seatbelt allows some broad reads on macOS

R needs system libraries, so the profile allows reads under several
system paths, including parts of `/usr`, `/Library/Frameworks`,
`/System/Library`, `/opt/homebrew`, and `/bin`. It also allows reading
file metadata anywhere, because R calls `stat()`. So the child can tell
whether a file exists and how big it is, even where it can’t read it.
Your home directory isn’t readable.

Don’t keep sensitive data in places every user can read. Credentials in
environment variables are covered by the clean environment (section 6).

### Apple has deprecated `sandbox-exec`

Apple has deprecated `sandbox-exec` and the Seatbelt profile language.
It still ships with current macOS (it’s there in macOS 27) and Apple’s
own tools use it, but it could disappear, and there’s no public
replacement for other programs.

If it goes away, securer warns you and runs without the OS sandbox.
Resource limits and the message checks still apply. Use
`sandbox_strict = TRUE` if you’d rather it stopped.

### `ulimit` is per process, not per session

`ulimit` values apply to each process separately. A child that forks
passes the limits on, but each fork counts as one process against
`nproc`. And `nproc` counts every process your user is running, not just
this session’s.

### The socket isn’t encrypted

Parent and child send plain JSON over the socket. Filesystem permissions
and the token keep other processes out, but nothing is encrypted.
Someone already running as your user could read the traffic.

The socket directory has `0700` permissions and a random name, and the
token blocks connections that didn’t come from the child. If an attacker
is already running code as your user, they can reach everything the
session can anyway.

### The syntax check is only advice

See section 8. Regular expressions flag harmless code and miss some
risky code. The OS sandbox does the real enforcement.

### `.securer_call_tool()` can still be called directly

The tool wrappers are locked, but child code can call
`.securer_call_tool()` itself to make any tool call it wants. The parent
still checks the tool name and arguments. Locking the wrappers stops
code from redefining them. It doesn’t limit tool access beyond what the
parent already enforces.

### Pools mean more processes to attack

`SecureSessionPool$new(size = 4)` starts four separate child processes,
each with its own socket, sandbox, and limits. A hole in the sandbox
affects all of them. A session that dies, for example by hitting a
resource limit, is restarted the next time it’s handed out, so you won’t
notice unless you look.

### Running without a sandbox

When `sandbox-exec` (macOS) or `bwrap` (Linux) can’t be found, securer
warns and runs without the sandbox. Resource limits, the message checks,
and the clean environment still apply. `sandbox_strict = TRUE` turns
this into an error.

### Code can still use resources up to the limits

Limits cap how much the code can use. They don’t stop it from using that
much. The defaults (60 seconds of CPU, 512 MB of memory, 50 MB files, 50
processes) may be more than you want. See “Tighten resource limits”
below.

### The `unlockBinding()` workarounds aren’t airtight

securer replaces
[`unlockBinding()`](https://rdrr.io/r/base/bindenv.html) and blocks
[`getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html)
and
[`getNativeSymbolInfo()`](https://rdrr.io/r/base/getNativeSymbolInfo.html).
Someone determined may still find another way to reach the original
[`base::unlockBinding`](https://rdrr.io/r/base/bindenv.html).

That wouldn’t get them far. Even if the child redefines
`.securer_call_tool()`, all it changes is how the child builds messages.
The parent checks every message on its own.

## Socket protocol

### Transport

|  |  |
|----|----|
| Socket type | Unix domain socket (`AF_UNIX`, `SOCK_STREAM`) |
| Path | `/tmp/securer_XXXXX/ipc.sock` on macOS and Linux, `%TEMP%\securer_XXXXX\ipc.sock` on Windows |
| Why `/tmp` | macOS limits socket paths to about 104 characters, and [`tempdir()`](https://rdrr.io/r/base/tempfile.html) can be much longer during `R CMD check` |
| Direction | Both ways. The parent creates the server and the child connects |
| Functions | [`processx::conn_create_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md) and [`processx::conn_connect_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md) |

### Connecting

1.  The parent creates the server socket at
    `/tmp/securer_XXXXX/ipc.sock`.
2.  The parent starts the child with `callr::r_session$new()`.
3.  The child connects to the path in `SECURER_SOCKET`.
4.  The parent accepts with
    [`processx::conn_accept_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md).
    This turns the server connection itself into the data connection,
    rather than returning a new one.
5.  The child sends the token from `SECURER_TOKEN`.
6.  The parent checks the token and gives up if it’s wrong.

### Messages

Each message is one line of JSON ending in `\n`.

A tool call, from child to parent:

``` json
{"type":"tool_call","tool":"add","args":{"a":1,"b":2}}
```

The result, from parent to child:

``` json
{"value":3}
```

An error, from parent to child:

``` json
{"error":"Unknown tool: nonexistent"}
```

### Order of events

Everything happens one step at a time. After sending a tool call, the
child waits on the socket. The parent runs the tool with your full
permissions and writes the result back, and then the child carries on.
There’s never more than one tool call in flight.

### Timeouts

The parent checks the socket and the child process every 200 ms. If
there’s a deadline, it also checks the time. Once the deadline passes,
it kills the child, closes the connection, and starts a new session.

## Advice for deployment

### Use `sandbox = TRUE` in production

Without the sandbox, the child can do anything the parent can.

### Tighten resource limits

The defaults (60 seconds of CPU, 512 MB of memory) are generous on
purpose. Set them to what your workload needs:

``` r

session <- SecureSession$new(
  sandbox = TRUE,
  limits = list(cpu = 10, memory = 128 * 1024 * 1024, nproc = 10)
)
```

### Use timeouts and tool call caps

``` r

session$execute(llm_code, timeout = 30, max_tool_calls = 50)
```

The timeout catches code that `ulimit -t` doesn’t, such as code waiting
on I/O or sleeping. The cap stops code from calling tools in a tight
loop.

### Be careful with your tool functions

Tool functions run in your session with your full permissions. Give each
one as little power as it needs. Check its inputs, and use parameterized
queries:

``` r

securer_tool("get_user", "Look up user by ID",
  fn = function(user_id) {
    stopifnot(is.numeric(user_id), user_id > 0)
    DBI::dbGetQuery(conn, "SELECT name, email FROM users WHERE id = ?",
                    params = list(user_id))
  },
  args = list(user_id = "numeric"))
```

### Turn on the audit log

``` r

session <- SecureSession$new(sandbox = TRUE, audit_log = "/var/log/securer/audit.jsonl")
```

The log records `session_start`, `session_close`, `session_restart`,
`execute_start`, `execute_complete`, `execute_error`, `execute_timeout`,
`tool_call`, and `tool_result` events.

### On Windows, use a container

Use the docker-spawn backend, or run R inside Docker or WSL2 with
bubblewrap, to get the file and network restrictions the Windows sandbox
doesn’t have.
