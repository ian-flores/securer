# Validate a list of tools

Accepts either a named list of bare functions (legacy format from
increment 1) or a list of
[`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
objects. Returns a named list with two components: `fns` (tool functions
keyed by name) and `arg_meta` (expected argument names keyed by tool
name).

## Usage

``` r
validate_tools(tools)
```

## Arguments

- tools:

  List of `securer_tool` objects or a named list of functions

## Value

A list with `fns` (named list of functions) and `arg_meta` (named list
of character vectors of expected arg names, `NULL` for legacy tools
without metadata)
