# securer

> \[!CAUTION\] **Alpha software.** This package is part of a broader
> effort by [Ian Flores Siaca](https://github.com/ian-flores) to develop
> proper AI infrastructure for the R ecosystem. It is under active
> development and should **not** be used in production until an official
> release is published. APIs may change without notice.

**Let LLMs write R code that calls your functions — safely.**

When an LLM generates R code, you need two things: a way for that code
to call back into your application (tool calls), and confidence that the
code can’t do anything dangerous (sandboxing). securer provides both.

``` r
# Simplest usage -- run R code in a sandbox
execute_r("1 + 1")
#> [1] 2
```

For tool calls, define functions the sandboxed code can use:

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

## Part of the secure-r-dev Ecosystem

securer is part of a 7-package ecosystem for building governed AI agents
in R:

                        ┌────────────────┐
                        │ >>> securer <<< │
                        └───────┬────────┘
              ┌─────────────────┼─────────────────┐
              │                 │                  │
       ┌──────▼──────┐  ┌──────▼──────┐  ┌───────▼────────┐
       │ securetools  │  │ secureguard │  │ securecontext   │
       └──────┬───────┘  └──────┬──────┘  └───────┬────────┘
              └─────────────────┼─────────────────┘
                        ┌───────▼──────┐
                        │   orchestr   │
                        └───────┬──────┘
              ┌─────────────────┼─────────────────┐
              │                                   │
       ┌──────▼──────┐                     ┌──────▼──────┐
       │ securetrace  │                    │ securebench  │
       └─────────────┘                     └─────────────┘

securer sits at the top of the stack, providing the sandboxed R
execution engine that other packages build on. securetools adds
pre-built tool definitions, secureguard adds guardrails, and orchestr
wires agents into workflows.

| Package                                                      | Role                                                    |
|--------------------------------------------------------------|---------------------------------------------------------|
| [securer](https://github.com/ian-flores/securer)             | Sandboxed R execution with tool-call IPC                |
| [securetools](https://github.com/ian-flores/securetools)     | Pre-built security-hardened tool definitions            |
| [secureguard](https://github.com/ian-flores/secureguard)     | Input/code/output guardrails (injection, PII, secrets)  |
| [orchestr](https://github.com/ian-flores/orchestr)           | Graph-based agent orchestration                         |
| [securecontext](https://github.com/ian-flores/securecontext) | Document chunking, embeddings, RAG retrieval            |
| [securetrace](https://github.com/ian-flores/securetrace)     | Structured tracing, token/cost accounting, JSONL export |
| [securebench](https://github.com/ian-flores/securebench)     | Guardrail benchmarking with precision/recall/F1 metrics |

## Installation

``` r
# install.packages("pak")
pak::pak("ian-flores/securer")

# Verify it works
library(securer)
execute_r("1 + 1")
#> [1] 2
```

## Why securer?

| Problem                                    | How securer solves it                                                      |
|--------------------------------------------|----------------------------------------------------------------------------|
| LLM code could access the filesystem       | OS sandbox blocks writes; reads restricted to R libraries                  |
| LLM code could make network requests       | Network access blocked via namespace isolation (Linux) or Seatbelt (macOS) |
| LLM code needs to call your APIs/databases | Register tool functions that execute on the host side, outside the sandbox |
| LLM code could run forever                 | Execution timeouts with automatic session recovery                         |
| LLM code could consume all memory          | Resource limits via ulimit (Linux/macOS) and Job Objects (Windows)         |
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

Constrain CPU, memory, file size, and more. Works with or without
sandbox mode on all platforms:

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

| Platform    | Sandbox                     | Network blocked | Filesystem restricted | Resource limits                  |
|-------------|-----------------------------|-----------------|-----------------------|----------------------------------|
| **Linux**   | bubblewrap (`bwrap`)        | Yes             | Yes                   | Yes (ulimit)                     |
| **macOS**   | Seatbelt (`sandbox-exec`)   | Yes             | Yes                   | Yes (ulimit)                     |
| **Windows** | Job Objects + env isolation | No              | No                    | Yes (memory, CPU, process count) |

All platforms support tool call IPC, execution timeouts, and code
pre-validation.

## Security

securer implements defense-in-depth with multiple layers: OS-level
sandboxing, authenticated IPC, resource limits, environment
sanitization, and input validation. For a detailed threat model and
security architecture, see
[`vignette("security-model", package = "securer")`](https://ian-flores.github.io/securer/articles/security-model.md).

To report security vulnerabilities, please email the maintainer directly
rather than filing a public issue.

## Documentation

- [`vignette("quickstart", package = "securer")`](https://ian-flores.github.io/securer/articles/quickstart.md)
  – installation and first examples
- [`vignette("sessions-and-tools", package = "securer")`](https://ian-flores.github.io/securer/articles/sessions-and-tools.md)
  – persistent sessions, streaming, pooling
- [`vignette("deployment", package = "securer")`](https://ian-flores.github.io/securer/articles/deployment.md)
  – sandboxing, resource limits, architecture
- [`vignette("security-model", package = "securer")`](https://ian-flores.github.io/securer/articles/security-model.md)
  – threat model and defense layers
- [`vignette("ellmer-integration", package = "securer")`](https://ian-flores.github.io/securer/articles/ellmer-integration.md)
  – using securer with ellmer LLM chats
- [`vignette("integration-examples", package = "securer")`](https://ian-flores.github.io/securer/articles/integration-examples.md)
  – Shiny, Plumber, and batch examples
- [`vignette("troubleshooting", package = "securer")`](https://ian-flores.github.io/securer/articles/troubleshooting.md)
  – common issues and solutions
- [pkgdown site](https://ian-flores.github.io/securer/) – API reference

## License

MIT
