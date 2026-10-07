# securer_tool S7 class

The S7 class behind `securer_tool()`. You normally create tools with
`securer_tool()` rather than with this class directly.

A tool is a function that code in the sandbox can call by name, but that
runs in your session. Pass a list of tools to
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
or
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md).

## Usage

``` r
securer_tool_class(
  name = character(0),
  description = character(0),
  fn = function() NULL,
  args = list()
)

securer_tool(name, description, fn, args = list())
```

## Arguments

- name:

  Character, the tool name (must be non-empty).

- description:

  Character, what the tool does. You can show this to an LLM so it knows
  when to use the tool.

- fn:

  The function that runs when the tool is called.

- args:

  Named list of argument names and their types, such as
  `list(city = "character")`. securer uses it to build a function with
  the same arguments in the child, and to check argument types. Allowed
  types are `"numeric"`, `"character"`, `"logical"`, `"integer"`,
  `"list"`, and `"data.frame"`.

## Value

A `securer_tool` object.

## Examples

``` r
tool <- securer_tool(
  "add", "Add two numbers",
  fn = function(a, b) a + b,
  args = list(a = "numeric", b = "numeric")
)
tool@name
#> [1] "add"
# "add"
```
