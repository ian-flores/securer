# Using securer with ellmer

## Overview

[ellmer](https://ellmer.tidyverse.org/) is an R package for chatting
with LLMs. securer integrates with ellmer’s tool-use system so an LLM
can execute R code in a sandboxed child process. The LLM writes code,
securer runs it safely, and the result flows back into the conversation.

[`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md)
is the bridge between the two packages. It wraps a `SecureSession` as an
ellmer tool definition that you register on a chat object.

## Quick start

``` r
library(securer)
library(ellmer)

chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool())
chat$chat("What is the sum of the first 100 prime numbers?")
```

That’s it. The LLM receives a tool called `execute_r_code` that accepts
a `code` string. When the model decides to use it, securer runs the code
in a sandboxed child process and returns the result. The sandbox blocks
filesystem writes and network access — the LLM can compute but not
exfiltrate.

## How it works

When you call
[`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md),
securer:

1.  Creates a `SecureSession` (or uses one you provide)
2.  Returns an ellmer `ToolDef` object with a single `code` argument
3.  The LLM sees the tool’s description and can choose to call it

When the LLM invokes the tool:

    LLM generates: execute_r_code(code = "mean(1:100)")
        |
        v
    ellmer calls securer's executor function
        |
        v
    securer sends code to sandboxed child process
        |
        v
    Child evaluates code, returns result
        |
        v
    securer formats result as a string
        |
        v
    ellmer passes result back to LLM
        |
        v
    LLM incorporates result into its response

Errors in the child (syntax errors, runtime errors, timeouts) are caught
and returned as `ContentToolResult(error = ...)`. This tells the LLM
something went wrong without crashing the chat loop — the model can try
again or explain the error.

## Adding securer tools

The real power comes from giving the LLM access to your own functions.
Define securer tools and pass them in:

``` r
tools <- list(
  securer_tool("query_db", "Query a database table by name",
    fn = function(table, limit) {
      con <- DBI::dbConnect(RSQLite::SQLite(), "data.db")
      on.exit(DBI::dbDisconnect(con))
      DBI::dbGetQuery(con, sprintf("SELECT * FROM %s LIMIT %d", table, limit))
    },
    args = list(table = "character", limit = "numeric")),

  securer_tool("list_tables", "List available database tables",
    fn = function() {
      con <- DBI::dbConnect(RSQLite::SQLite(), "data.db")
      on.exit(DBI::dbDisconnect(con))
      DBI::dbListTables(con)
    },
    args = list())
)

chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool(tools = tools))
chat$chat("What tables are available? Show me the first 5 rows of each.")
```

The LLM’s code runs sandboxed, but `query_db()` and `list_tables()`
execute on the host with full database access. The sandbox ensures the
LLM can only interact with your data through the tools you define.

## Configuring the session

[`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md)
accepts the same configuration as `SecureSession`:

``` r
tool_def <- securer_as_ellmer_tool(
  tools = tools,
  sandbox = TRUE,       # OS-level sandbox (default)
  limits = list(        # Resource limits
    cpu = 30,
    memory = 512 * 1024 * 1024
  ),
  timeout = 15          # Per-execution timeout in seconds (default: 30)
)
```

### Sandbox

With `sandbox = TRUE` (the default), the child process runs inside an
OS-level sandbox:

- **macOS**: Seatbelt blocks network access and filesystem writes
  outside `/tmp`
- **Linux**: bubblewrap provides full namespace isolation
- **Windows**: Environment-variable isolation only (a warning is issued)

Set `sandbox = FALSE` if you trust the LLM’s code or are running in an
environment where sandboxing isn’t available.

### Resource limits

The `limits` argument applies `ulimit`-based caps to the child process.
This prevents the LLM from writing code that consumes all available CPU
or memory:

| Limit    | Description            |
|----------|------------------------|
| `cpu`    | CPU time (seconds)     |
| `memory` | Virtual memory (bytes) |
| `fsize`  | Max file size (bytes)  |
| `nproc`  | Max processes          |
| `nofile` | Max open files         |
| `stack`  | Stack size (bytes)     |

### Timeout

The `timeout` parameter (default 30 seconds) sets a wall-clock deadline
for each code execution. If the LLM writes an infinite loop, securer
kills the child process and returns an error to ellmer. The session
automatically recovers and is reusable for subsequent tool calls.

## Using a pre-existing session

If you need more control over the session lifecycle, create one yourself
and pass it in:

``` r
session <- SecureSession$new(
  tools = tools,
  sandbox = TRUE,
  verbose = TRUE  # Log tool calls and execution timing
)

chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool(session = session))

chat$chat("Analyze the sales table and compute monthly totals.")
chat$chat("Now plot the trend.")  # Same session, state persists

# You own the session --- close it when done
session$close()
```

When you provide your own session, securer does not create or close one
internally. This is useful when you want:

- **Verbose logging** to see tool calls and timing
- **Audit logging** (`audit_log = "path.jsonl"`) for compliance
- **State persistence** across multiple chat turns
- **Session reuse** across multiple chat objects

## Result formatting

securer converts R values to strings before returning them to the LLM:

| R type     | Formatting                                                                      |
|------------|---------------------------------------------------------------------------------|
| `NULL`     | `"NULL"`                                                                        |
| Scalar     | [`as.character()`](https://rdrr.io/r/base/character.html) (e.g., `42` → `"42"`) |
| Data frame | [`print()`](https://rdrr.io/r/base/print.html) output, truncated at 30 rows     |
| Other      | `capture.output(print())`, truncated at 50 lines                                |

Truncation prevents large results from consuming the LLM’s context
window.

## Error handling

Errors are surfaced to the LLM as tool errors, not R exceptions. This
means the chat doesn’t crash — the LLM sees the error message and can
react:

``` r
chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool(sandbox = FALSE))

# The LLM might generate code with a bug. securer catches the error
# and returns it as a tool result. The LLM sees the error message
# and can fix its code and try again.
chat$chat("Divide 1 by 0 and tell me what happens in R")
```

Error scenarios handled:

- **Syntax errors** in the LLM’s code
- **Runtime errors** (e.g.,
  [`stop()`](https://rdrr.io/r/base/stop.html), missing variables)
- **Timeout** (code runs too long)
- **Dead session** (child process crashed)
- **Type mismatches** in tool arguments (e.g., passing a string where
  numeric is expected)

In all cases, the LLM receives a descriptive error message and can
decide how to proceed.

## Example: data analysis assistant

A complete example combining securer, ellmer, and custom tools:

``` r
library(securer)
library(ellmer)

# Define tools the LLM can use
tools <- list(
  securer_tool("load_csv", "Load a CSV file and return as data frame",
    fn = function(path) {
      if (!file.exists(path)) stop("File not found: ", path)
      read.csv(path)
    },
    args = list(path = "character")),

  securer_tool("save_plot", "Save the current plot to a PNG file",
    fn = function(filename) {
      dev.copy(png, filename, width = 800, height = 600)
      dev.off()
      paste("Plot saved to", filename)
    },
    args = list(filename = "character"))
)

# Create a sandboxed execution environment
chat <- chat_openai(
  system_prompt = paste(
    "You are a data analysis assistant.",
    "You have access to an R execution environment via the execute_r_code tool.",
    "Use it to load data, compute statistics, and create visualizations.",
    "Available tools inside R: load_csv(path), save_plot(filename)."
  )
)
chat$register_tool(securer_as_ellmer_tool(
  tools = tools,
  timeout = 60,
  limits = list(memory = 1024 * 1024 * 1024)  # 1 GB
))

# Multi-turn conversation with persistent state
chat$chat("Load sales.csv and show me a summary")
chat$chat("What's the correlation between price and quantity?")
chat$chat("Create a scatter plot of price vs quantity")
```

Each `chat$chat()` call may trigger multiple rounds of code execution.
The LLM writes code, sees the result, and can write more code — all
within the same sandboxed session with persistent state.

## Using with other LLM providers

ellmer supports multiple LLM backends. securer works with any of them:

``` r
# OpenAI
chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool())

# Anthropic
chat <- chat_anthropic()
chat$register_tool(securer_as_ellmer_tool())

# Ollama (local)
chat <- chat_ollama(model = "llama3")
chat$register_tool(securer_as_ellmer_tool())
```

The tool definition is provider-agnostic. Any model that supports tool
use will see `execute_r_code` and can call it.

## Session pooling

For applications that handle multiple concurrent users, combine session
pooling with ellmer:

``` r
# For raw code execution across concurrent users, use the pool directly.
# pool$execute() handles session acquisition and release internally.
pool <- SecureSessionPool$new(size = 4, tools = tools, sandbox = TRUE)

handle_user_code <- function(code) {
  pool$execute(code, timeout = 30)
}

# For ellmer integration with concurrent users, create a separate
# SecureSession per request. Each session is cleaned up on GC.
handle_user_chat <- function(user_message) {
  chat <- chat_openai()
  tool <- securer_as_ellmer_tool(tools = tools, sandbox = TRUE, timeout = 30)
  chat$register_tool(tool)
  chat$chat(user_message)
}
```

The pool pre-warms sessions for low-latency raw code execution via
`pool$execute()`. For ellmer chat integration,
[`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md)
creates and manages its own session (cleaned up automatically when
garbage collected).
