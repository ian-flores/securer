# Generate wrapper code for tools in the child process

For each
[`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
object, generates an R function in the child's global environment that
delegates to `.securer_call_tool()` with the tool name and arguments.

## Usage

``` r
generate_tool_wrappers(tools)
```

## Arguments

- tools:

  List of `securer_tool` objects

## Value

Character string of R code that creates wrapper functions
