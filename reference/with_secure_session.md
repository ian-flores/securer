# Run a function with a SecureSession that closes itself

Starts a
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md),
passes it to `fn`, and closes it when `fn` returns or fails. Use it when
you want several calls to share one session, for example to build up
variables across calls, without having to remember to close it.

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
