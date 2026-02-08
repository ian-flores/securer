# Execute R code securely with tool support

A convenience wrapper that creates a
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md),
executes code, and returns the result. The session is automatically
closed when done.

## Usage

``` r
execute_r(
  code,
  tools = list(),
  timeout = 30,
  sandbox = TRUE,
  limits = NULL,
  verbose = FALSE,
  validate = TRUE,
  audit_log = NULL
)
```

## Arguments

- code:

  Character string of R code to execute.

- tools:

  List of tools created with
  [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md),
  or a named list of functions (legacy format).

- timeout:

  Timeout in seconds for the execution, or `NULL` for no timeout
  (default 30).

- sandbox:

  Logical, whether to enable OS-level sandboxing (default TRUE).

- limits:

  Optional named list of resource limits (see
  [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
  for details).

- verbose:

  Logical, whether to emit diagnostic messages via
  [`message()`](https://rdrr.io/r/base/message.html). Useful for
  debugging. Users can suppress with
  [`suppressMessages()`](https://rdrr.io/r/base/message.html).

- validate:

  Logical, whether to pre-validate the code for syntax errors before
  sending it to the child process (default `TRUE`).

- audit_log:

  Optional path to a JSONL file for persistent audit logging (default
  `NULL`, no file logging).

## Value

The result of evaluating `code` in the secure session.

## Examples

``` r
if (FALSE) { # \dontrun{
# Simple computation
execute_r("1 + 1")

# With tools
result <- execute_r(
  code = 'add(2, 3)',
  tools = list(
    securer_tool("add", "Add two numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )
)

# With resource limits
execute_r("1 + 1", limits = list(cpu = 10, memory = 256 * 1024 * 1024))
} # }
```
