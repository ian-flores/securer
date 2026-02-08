# Create a tool definition

Defines a named tool with a function implementation and typed argument
metadata. Tool objects are passed to
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
or
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
so that code running in the sandboxed child process can call the tool by
name and the parent process executes the actual function.

## Usage

``` r
securer_tool(name, description, fn, args = list())
```

## Arguments

- name:

  Character, the tool name (must be non-empty).

- description:

  Character, description of what the tool does.

- fn:

  Function that implements the tool.

- args:

  Named list mapping argument names to type strings (e.g.
  `list(city = "character")`). Used to generate wrapper functions in the
  child process with the correct formal arguments.

## Value

A `securer_tool` object (a list with class `"securer_tool"`).

## Examples

``` r
tool <- securer_tool(
  "add", "Add two numbers",
  fn = function(a, b) a + b,
  args = list(a = "numeric", b = "numeric")
)
tool$name
#> [1] "add"
# "add"
```
