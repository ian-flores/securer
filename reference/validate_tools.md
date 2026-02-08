# Validate a list of tools

Accepts either a named list of bare functions (legacy format from
increment 1) or a list of
[`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
objects. Returns a named list of tool functions keyed by tool name.

## Usage

``` r
validate_tools(tools)
```

## Arguments

- tools:

  List of `securer_tool` objects or a named list of functions

## Value

Named list of tool functions (keyed by tool name)
