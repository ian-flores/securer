# Format an R value as a tool result string

Converts R objects into a human-readable string suitable for returning
to an LLM as a tool result. Data frames get a truncated print
representation; scalars are coerced directly; other objects use
`capture.output(print(...))`.

## Usage

``` r
format_tool_result(value)
```

## Arguments

- value:

  Any R object returned by code execution.

## Value

A character string.
