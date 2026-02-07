# securer

Secure R code execution with tool-call IPC. Designed for LLM agents that generate R code calling registered tools — execution pauses at each tool call, the host fulfills it, and execution resumes.

Wraps `callr::r_session` with a bidirectional Unix domain socket protocol for pause/resume and OS-level sandboxing.

## Installation

```r
# install.packages("pak")
pak::pak("posit-dev/securer")
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

### Linux

Planned: bubblewrap (`bwrap`) with namespace isolation, read-only mounts, no network. Currently falls back to unsandboxed with a warning.

### Windows / Other

Falls back to unsandboxed execution with a warning.

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

## Dependencies

- [callr](https://callr.r-lib.org/) (>= 3.7.0) — child R session management
- [processx](https://processx.r-lib.org/) (>= 3.8.0) — Unix domain sockets
- [R6](https://r6.r-lib.org/) — class system
- [jsonlite](https://jeroen.r-universe.dev/jsonlite) — IPC message serialization

## License

MIT
