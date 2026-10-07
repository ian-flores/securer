# Sessions and tools

This vignette covers sessions you keep open, what happens to output and
errors, the audit log, and session pools. If you’re new to securer,
start with
[`vignette("quickstart")`](https://ian-flores.github.io/securer/articles/quickstart.md).

## Persistent sessions

`SecureSession` keeps one child R process running across many
`$execute()` calls. Variables you create in one call are still there in
the next:

``` r

library(securer)

tools <- list(
  securer_tool("add", "Add two numbers",
    fn = function(a, b) a + b,
    args = list(a = "numeric", b = "numeric"))
)

session <- SecureSession$new(tools = tools, sandbox = TRUE)

session$execute("x <- add(10, 20)")
session$execute("x * 2")
#> [1] 60

session$close()
```

Call `$close()` when you’re done. Or use
[`with_secure_session()`](https://ian-flores.github.io/securer/reference/with_secure_session.md),
which closes the session for you, even if the code fails:

``` r

result <- with_secure_session(function(session) {
  session$execute("x <- 10")
  session$execute("x * 2")
}, sandbox = FALSE)
```

## Limits for agents

A few options are there mainly for code written by an LLM. `$execute()`
refuses code longer than `max_code_length` characters (100,000 by
default). In `$new()`, `max_executions` caps how many times a session
can run code, and `pre_execute_hook` is a function that sees the code
first and can block it by returning `FALSE`. `sanitize_errors = TRUE`
removes file paths, process IDs, and host names from error messages
before you see them, so they don’t end up back in the model’s context.

``` r

session <- SecureSession$new(
  max_executions = 100,
  pre_execute_hook = function(code) {
    # Block code that mentions system()
    !grepl("system\\(", code)
  },
  sanitize_errors = TRUE
)
```

[`vignette("security-model")`](https://ian-flores.github.io/securer/articles/security-model.md)
explains how these fit with the sandbox.

## Execution timeouts

`$execute()` takes a `timeout` in seconds (30 by default). When time
runs out, securer kills the child process and starts a new one, so the
session still works:

``` r

session <- SecureSession$new()
session$execute("Sys.sleep(60)", timeout = 5)
#> Error: Execution timed out after 5 seconds
session$is_alive()
#> [1] TRUE
session$close()
```

## Error handling

An error in the sandboxed code or in a tool comes back to you as an
ordinary R error:

``` r

execute_r('stop("something went wrong")')
#> Error: something went wrong

execute_r("nonexistent_tool()", tools = list())
#> Error: could not find function "nonexistent_tool"
```

## Streaming output

To see output while the code is still running, pass an `output_handler`.
It gets each line as it’s printed:

``` r

session <- SecureSession$new()
session$execute(
  'for (i in 1:5) cat("Step", i, "\\n")',
  output_handler = function(line) message("[child] ", line)
)
session$close()
```

Whether or not you pass a handler, the printed output is also attached
to the result as `attr(result, "output")`.

## Output and tool call limits

`max_output_lines` and `max_tool_calls` limit a single `$execute()`
call:

``` r

session <- SecureSession$new()

# Cap accumulated output lines
result <- session$execute(
  'for (i in 1:1000) cat("line", i, "\\n")',
  max_output_lines = 100
)

# Cap tool calls in one execution
session$execute("for (i in 1:10) add(i, i)", max_tool_calls = 5)
#> Error: Maximum tool calls (5) exceeded

session$close()
```

## Session lifecycle

`$restart()` replaces the child process with a fresh one. `$is_alive()`
tells you whether the child is running:

``` r

session <- SecureSession$new(sandbox = FALSE)

session$execute("x <- 42")
session$restart()

# State is gone after restart
session$execute("exists('x')")
#> [1] FALSE

session$is_alive()
#> [1] TRUE
session$close()
```

## Audit logging

Pass a file path as `audit_log` and the session writes one JSON object
per line for each thing that happens:

``` r

session <- SecureSession$new(audit_log = "securer-audit.jsonl")
session$execute("1 + 1")
session$close()
```

Every line has `timestamp`, `event`, and `session_id`, plus fields that
depend on the event:

| Event | Extra fields |
|----|----|
| `session_start` | `sandbox`, `pid` |
| `session_close`, `session_restart` | none |
| `execute_start` | `code` |
| `execute_complete` | `elapsed` |
| `execute_error` | `error`, `elapsed` |
| `execute_timeout` | `timeout_secs` |
| `tool_call` | `tool`, `args` |
| `tool_result` | `tool`, `error`, `result_summary`, `elapsed_secs` |

A `tool_call` line looks like this:

``` json
{"timestamp":"2024-01-15T10:30:00.000Z","event":"tool_call","session_id":"sess_abc123","tool":"add","args":{"a":1,"b":2}}
```

Only you can read or write the log file (permissions `0600`). Code
longer than 10,000 characters is cut short in the log.

## Session pooling

### Why use a pool

A new `SecureSession` has to start R, set up the sandbox, and open the
socket. That takes half a second to a second. In a Plumber API or a
Shiny app with many users, paying that on every request adds up. A pool
starts a fixed number of sessions once and hands them out as requests
come in.

### How a pool works

     Initialize          Acquire            Execute           Release
    +-------------+   +-------------+   +-------------+   +-------------+
    | Pre-warm N  |-->| Caller gets |-->| Run code in |-->| Return to   |
    | sessions at |   | idle session|   | acquired    |   | idle pool   |
    | startup     |   | from pool   |   | session     |   | (or restart |
    |             |   |             |   |             |   |  if dead)   |
    +-------------+   +-------------+   +-------------+   +-------------+

`SecureSessionPool` starts its sessions when you create it:

``` r

pool <- SecureSessionPool$new(size = 4, sandbox = TRUE)

pool$execute("1 + 1")
#> [1] 2

pool$status()  # returns list(total, busy, idle, dead)
pool$close()
```

Sessions in a pool keep their variables between uses. If different users
share the pool, set `reset_between_uses = TRUE` so each session restarts
after every call and one caller can’t see another’s data:

``` r

pool <- SecureSessionPool$new(
  size = 2,
  sandbox = FALSE,
  reset_between_uses = TRUE
)

pool$execute("x <- 99")
pool$execute("exists('x')")
#> [1] FALSE

pool$close()
```

If a session has died, the pool restarts it before handing it out. The
pool isn’t thread-safe. With `parallel` or `future`, give each worker
its own pool.
