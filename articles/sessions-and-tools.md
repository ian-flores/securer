# Sessions and Tools

This vignette covers session lifecycle, output handling, audit logging,
and session pooling. See also
[`vignette("quickstart")`](https://ian-flores.github.io/securer/articles/quickstart.md)
and
[`vignette("security-model")`](https://ian-flores.github.io/securer/articles/security-model.md).

## Persistent sessions

`SecureSession` keeps a child R process alive across multiple
`$execute()` calls. State persists between executions:

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

Always call `$close()` when done, or use
[`with_secure_session()`](https://ian-flores.github.io/securer/reference/with_secure_session.md)
for automatic cleanup:

``` r
result <- with_secure_session(function(session) {
  session$execute("x <- 10")
  session$execute("x * 2")
}, sandbox = FALSE)
```

## Safety features for agent workflows

`SecureSession` includes features for hardening LLM agent deployments:

- **`max_code_length`** (`$execute()`): Reject code exceeding a
  character limit (default 100,000).
- **`max_executions`** (`$new()`): Cap total `$execute()` calls per
  session.
- **`pre_execute_hook`** (`$new()`): Callback returning `FALSE` to block
  execution.
- **`sanitize_errors`** (`$new()`): Strip paths, PIDs, and hostnames
  from errors.

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

See
[`vignette("security-model")`](https://ian-flores.github.io/securer/articles/security-model.md)
for the full threat model and defense layers.

## Execution timeouts

`$execute()` accepts a `timeout` in seconds (default 30). On timeout the
child is killed and the session auto-recovers:

``` r
session <- SecureSession$new()
session$execute("Sys.sleep(60)", timeout = 5)
#> Error: Execution timed out
session$is_alive()
#> [1] TRUE
session$close()
```

## Error handling

Errors in the child process, in tool execution, and from unknown tool
names are all propagated to the host as standard R errors:

``` r
execute_r('stop("something went wrong")')
#> Error: something went wrong

execute_r("nonexistent_tool()", tools = list())
#> Error: Unknown tool: nonexistent_tool
```

## Streaming output

Pass `output_handler` to receive child output as it arrives:

``` r
session <- SecureSession$new()
session$execute(
  'for (i in 1:5) cat("Step", i, "\\n")',
  output_handler = function(line) message("[child] ", line)
)
session$close()
```

Output is always available as `attr(result, "output")` on the return
value.

## Output and tool call limits

Both `max_output_lines` and `max_tool_calls` are per-execution caps:

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

`$restart()` resets the child process; `$is_alive()` checks if it is
running:

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

Pass `audit_log` to the constructor to write structured JSONL entries:

``` r
session <- SecureSession$new(audit_log = "securer-audit.jsonl")
session$execute("1 + 1")
session$close()
```

Each line is a JSON object with `timestamp`, `event`, and `session_id`
fields plus event-specific data. Events: `session_start` (pid),
`session_close`, `session_restart`, `execute_start` (code),
`execute_complete` (elapsed), `execute_error` (error), `execute_timeout`
(timeout_secs), `tool_call` (tool, args), `tool_result` (tool, elapsed).
Example:

``` json
{"timestamp":"2024-01-15T10:30:00.000Z","event":"tool_call","session_id":"sess_abc123","tool":"add","args":{"a":1,"b":2}}
```

The log file is created with `0600` permissions. Code fields longer than
10,000 characters are truncated.

## Session pooling

`SecureSessionPool` pre-warms multiple sessions for low-latency
execution:

``` r
pool <- SecureSessionPool$new(size = 4, sandbox = TRUE)

pool$execute("1 + 1")
#> [1] 2

pool$status()  # returns list(total, busy, idle, dead)
pool$close()
```

Set `reset_between_uses = TRUE` to restart sessions after each
execution, preventing state leakage between callers:

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

Dead sessions are automatically restarted on acquire. The pool is
**not** thread-safe — create separate instances when using `parallel` or
`future`.
