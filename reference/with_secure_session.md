# Execute code with an auto-managed SecureSession

Creates a
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md),
passes it to a user function, and guarantees cleanup via
[`on.exit()`](https://rdrr.io/r/base/on.exit.html). This is useful when
you need to run multiple executions on the same session (e.g., building
up state across calls) without worrying about leaked processes.

## Usage

``` r
with_secure_session(fn, tools = list(), sandbox = TRUE, ...)
```

## Arguments

- fn:

  A function that receives a
  [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
  as its first argument.

- tools:

  List of
  [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  objects to register in the session.

- sandbox:

  Logical, whether to enable OS-level sandboxing (default `TRUE`).

- ...:

  Additional arguments passed to
  [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)`$new()`.

## Value

The return value of `fn(session)`.

## Examples

``` r
# \donttest{
# Run multiple commands on the same session
result <- with_secure_session(function(session) {
  session$execute("x <- 10")
  session$execute("x * 2")
}, sandbox = FALSE)

# With tools
result <- with_secure_session(
  fn = function(session) {
    session$execute("add(2, 3)")
  },
  tools = list(
    securer_tool("add", "Add two numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  ),
  sandbox = FALSE
)
# }
```
