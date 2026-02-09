# Default resource limits for sandboxed sessions

Returns sensible defaults applied automatically when `sandbox = TRUE`
and no explicit `limits` are provided. Users can override with
`limits = list()` (empty list) to explicitly disable limits.

## Usage

``` r
default_limits()
```

## Value

A named list of resource limits.
