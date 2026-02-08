# securer

Secure R code execution with tool-call IPC. Designed for LLM agents that generate R code calling registered tools — execution pauses at each tool call, the host fulfills it, and execution resumes.

Wraps `callr::r_session` with a bidirectional Unix domain socket protocol for pause/resume and OS-level sandboxing.

## Installation

```r
# install.packages("pak")
pak::pak("ian-flores/securer")
```

## Quick Start

```r
library(securer)

# Define tools the LLM code can call
tools <- list(
  securer_tool("get_weather", "Get weather for a city",
    fn = function(city) list(temp = 72, condition = "sunny"),
    args = list(city = "character")),
  securer_tool("add", "Add two numbers",
    fn = function(a, b) a + b,
    args = list(a = "numeric", b = "numeric"))
)

# One-liner: execute code in a sandboxed session
result <- execute_r(
  code = '
    weather <- get_weather("Boston")
    paste("Temperature:", weather$temp)
  ',
  tools = tools
)
```

## Session-Based Usage

For multiple executions, reuse a session to avoid startup overhead:

```r
session <- SecureSession$new(tools = tools, sandbox = TRUE)

result1 <- session$execute('add(2, 3)')
result2 <- session$execute('
  x <- add(10, 20)
  x * 2
')

session$close()
```

## How It Works

```
┌─────────────────────┐        ┌─────────────────────┐
│     Parent (host)    │        │   Child (sandboxed)  │
│                      │        │                      │
│  1. Send code ───────┼───────>│  2. eval(code)       │
│                      │        │                      │
│                      │  UDS   │  3. Code calls       │
│  5. Execute tool <───┼────────│     get_weather()    │
│     on host side     │        │     → pauses         │
│                      │        │                      │
│  6. Send result ─────┼───────>│  7. Resumes with     │
│                      │        │     tool result      │
│                      │  fd3   │                      │
│  9. Receive final <──┼────────│  8. Returns final    │
│     result           │        │     value            │
└─────────────────────┘        └─────────────────────┘
```

1. Parent creates a Unix domain socket and starts a `callr::r_session` child process
2. Child connects to the socket on startup
3. Parent sends LLM-generated code via `$call()`
4. When code calls a registered tool, the child writes a JSON request to the UDS and blocks
5. Parent reads the request, executes the tool function locally, writes the result back
6. Child receives the result and continues execution
7. Final result returns via callr's normal fd3 channel

## Sandbox

When `sandbox = TRUE`, the child R process runs inside OS-level restrictions:

### macOS (Seatbelt)

Uses `sandbox-exec` with a generated Seatbelt profile:

- **File writes blocked** except to temp directories
- **Network access blocked** (no TCP/UDP)
- **File reads allowed** (R needs access to system libs, packages)
- **Unix domain sockets allowed** (IPC with parent)

```r
session <- SecureSession$new(sandbox = TRUE)

# This works:
session$execute("1 + 1")

# This is blocked (no network):
session$execute('readLines(url("http://example.com"))')
# Error: Operation not permitted

# This is blocked (no file write outside temp):
session$execute('writeLines("hack", "~/evil.txt")')
# Error: Operation not permitted

session$close()
```

### Linux (bubblewrap)

Uses `bwrap` (bubblewrap) with full namespace isolation:

- **All namespaces isolated** (PID, net, user, mount, UTS, IPC)
- **Network access blocked** via network namespace isolation
- **Filesystem restricted** -- system libraries and R are mounted read-only; `/tmp` is writable
- **R package libraries** are bind-mounted read-only automatically

Requires `bwrap` to be installed (e.g. `apt install bubblewrap`). Falls back to unsandboxed with a warning if not found.

### Windows

Provides environment-variable isolation only:

- Clears `R_LIBS_USER`, `R_ENVIRON_USER`, `R_PROFILE_USER`
- Redirects `HOME` and `TMPDIR` to a clean temp directory

No filesystem or network restrictions are enforced. A warning is issued when `sandbox = TRUE`.

## Tool Definition

Tools are defined with `securer_tool()`:

```r
my_tool <- securer_tool(
  name = "query_db",
  description = "Query a database table",
  fn = function(table, limit) {
    head(get(table, "package:datasets"), n = limit)
  },
  args = list(table = "character", limit = "numeric")
)
```

- `name` — function name available to LLM code in the child process
- `description` — metadata for LLM tool-use prompts
- `fn` — the actual implementation, runs on the **parent** side (outside the sandbox)
- `args` — named list of argument types, used to generate typed wrapper functions in the child

## Resource Limits

Apply `ulimit`-based caps to the child process regardless of whether the sandbox is enabled:

```r
result <- execute_r(
  "Sys.sleep(0.1); 42",
  limits = list(cpu = 10, memory = 256 * 1024 * 1024)
)
```

Supported limits:

| Name     | Unit    | Description                 |
|----------|---------|-----------------------------|
| `cpu`    | seconds | CPU time                    |
| `memory` | bytes   | Virtual address space       |
| `fsize`  | bytes   | Maximum file size           |
| `nproc`  | count   | Maximum processes           |
| `nofile` | count   | Maximum open files          |
| `stack`  | bytes   | Stack size                  |

## Documentation

See `vignette("getting-started", package = "securer")` for a detailed
walkthrough of sessions, tools, sandboxing, and resource limits.

## Dependencies

- [callr](https://callr.r-lib.org/) (>= 3.7.0) — child R session management
- [processx](https://processx.r-lib.org/) (>= 3.8.0) — Unix domain sockets
- [R6](https://r6.r-lib.org/) — class system
- [jsonlite](https://jeroen.r-universe.dev/jsonlite) — IPC message serialization

## License

MIT
