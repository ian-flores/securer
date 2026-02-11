# securer

> \[!NOTE\] **Beta release (0.1.0).** The core API is stabilizing but
> may still change. Feedback and bug reports welcome at [GitHub
> Issues](https://github.com/ian-flores/securer/issues).

**Let LLMs write R code that calls your functions — safely.**

When an LLM generates R code, you need two things: a way for that code
to call back into your application (tool calls), and confidence that the
code can’t do anything dangerous (sandboxing). securer provides both.

``` r
library(securer)

# Your functions become tools the LLM's code can call
tools <- list(
  securer_tool("query_db", "Query a database table",
    fn = function(table, limit) head(get(table, "package:datasets"), limit),
    args = list(table = "character", limit = "numeric"))
)

# LLM-generated code runs sandboxed — tool calls pause, execute on your side, resume
result <- execute_r('
  data <- query_db("mtcars", 5)
  mean(data$mpg)
', tools = tools, sandbox = TRUE)
```

The child R process is sandboxed at the OS level. Tool functions execute
on the host side, outside the sandbox, with full access to your
resources. The LLM’s code never touches your filesystem, network, or
data directly.

## Installation

``` r
# install.packages("pak")
pak::pak("ian-flores/securer")
```

## Why securer?

| Problem                                    | How securer solves it                                                      |
|--------------------------------------------|----------------------------------------------------------------------------|
| LLM code could access the filesystem       | OS sandbox blocks writes; reads restricted to R libraries                  |
| LLM code could make network requests       | Network access blocked via namespace isolation (Linux) or Seatbelt (macOS) |
| LLM code needs to call your APIs/databases | Register tool functions that execute on the host side, outside the sandbox |
| LLM code could run forever                 | Execution timeouts with automatic session recovery                         |
| LLM code could consume all memory          | Resource limits (CPU, memory, file size, processes) via ulimit             |
| LLM code has syntax errors                 | Pre-validation catches parse errors before execution                       |

## How It Works

    ┌──────────────────────┐        ┌──────────────────────┐
    │    Parent (host)      │        │  Child (sandboxed R)  │
    │                       │        │                       │
    │  1. Send code ────────┼───────>│  2. eval(code)        │
    │                       │  UDS   │                       │
    │  3. Execute tool  <───┼────────│  Code calls tool()    │
    │     (your function)   │        │  → pauses on socket   │
    │                       │        │                       │
    │  4. Send result ──────┼───────>│  5. Resumes with      │
    │                       │        │     tool result       │
    │                       │        │                       │
    │  6. Receive final <───┼────────│  Returns final value  │
    │     result            │        │                       │
    └──────────────────────┘        └──────────────────────┘

Communication happens over a Unix domain socket. Tool calls are
synchronous: the child blocks while the parent fulfills the request.

## Features

### Persistent Sessions

Reuse a session across multiple executions to avoid startup overhead:

``` r
session <- SecureSession$new(tools = tools, sandbox = TRUE)

session$execute('query_db("iris", 3)')
session$execute('query_db("mtcars", 5)')

session$close()
```

### Session Pooling

Pre-warm multiple sessions for low-latency concurrent execution:

``` r
pool <- SecureSessionPool$new(size = 4, tools = tools, sandbox = TRUE)

result <- pool$execute('query_db("iris", 3)')

pool$close()
```

### Resource Limits

Constrain CPU, memory, and file size regardless of sandbox mode:

``` r
result <- execute_r("1 + 1",
  limits = list(cpu = 10, memory = 256 * 1024 * 1024)
)
```

### Execution Timeouts

Kill long-running code automatically. The session recovers and is
reusable:

``` r
session <- SecureSession$new()
session$execute("Sys.sleep(100)", timeout = 5)
# Error: Execution timed out after 5 seconds
session$execute("1 + 1")  # still works
```

### Code Pre-Validation

Catch syntax errors before sending code to the child process:

``` r
session$execute("if (TRUE {")  # immediate error, no child round-trip
```

### ellmer Integration

Use securer as a code execution tool in
[ellmer](https://ellmer.tidyverse.org/) LLM chats:

``` r
library(ellmer)
chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool())
chat$chat("Calculate the mean of 1 through 100 using R")
```

### Audit Logging

Write structured JSONL logs of all session events for compliance and
debugging:

``` r
session <- SecureSession$new(audit_log = "session.jsonl")
```

### Verbose Logging

Debug session behavior with human-readable
[`message()`](https://rdrr.io/r/base/message.html) output:

``` r
session <- SecureSession$new(verbose = TRUE)
# [securer] Session started (sandbox=FALSE, pid=1234)
# [securer] Tool call: query_db(table="iris", limit=3)
# [securer] Execution complete (0.5s)
```

## Platform Support

| Platform    | Sandbox                   | Network blocked           | Filesystem restricted     |
|-------------|---------------------------|---------------------------|---------------------------|
| **Linux**   | bubblewrap (`bwrap`)      | Yes (namespace isolation) | Yes (read-only mounts)    |
| **macOS**   | Seatbelt (`sandbox-exec`) | Yes (IP denied)           | Yes (writes to /tmp only) |
| **Windows** | Environment isolation     | No                        | No                        |

Linux and macOS provide full OS-level sandboxing. Windows provides
environment variable isolation only (clean HOME, empty R_LIBS_USER). All
platforms support resource limits and tool call IPC.

## Documentation

- [`vignette("getting-started", package = "securer")`](https://ian-flores.github.io/securer/articles/getting-started.md)
  — full walkthrough
- [pkgdown site](https://ian-flores.github.io/securer/) — API reference

## License

MIT
