# Execute R code securely with tool support

Starts a
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md),
runs `code` in it, and returns the result. The session is closed
afterwards, even if the code fails.

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
  sandbox_strict = FALSE,
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

  Logical, whether to print what the session is doing with
  [`message()`](https://rdrr.io/r/base/message.html). Handy for
  debugging. Wrap the call in
  [`suppressMessages()`](https://rdrr.io/r/base/message.html) to hide
  them.

- validate:

  Logical, whether to check the code for syntax errors before sending it
  to the child process (default `TRUE`).

- sandbox_strict:

  Logical, whether to stop with an error if the sandbox tools aren't
  available (default `FALSE`). See
  [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md).

- audit_log:

  Optional path to a JSONL file to log session events to. The default,
  `NULL`, writes no log.

## Value

The value of the last expression in `code`.

## Examples

``` r
# \donttest{
# Simple computation
execute_r("1 + 1", sandbox = FALSE)
#> [1] 2

# With tools
result <- execute_r(
  code = 'add(2, 3)',
  tools = list(
    securer_tool("add", "Add two numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  ),
  sandbox = FALSE
)
# }
if (FALSE) { # \dontrun{
# With resource limits (Unix only)
execute_r("1 + 1", limits = list(cpu = 10, memory = 256 * 1024 * 1024))
} # }
```
