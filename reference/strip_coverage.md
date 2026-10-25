# Remove covr instrumentation from a function

Under covr, every expression is wrapped as
`if (TRUE) { covr:::count(id); expr }`. Deparsing that breaks else-if
chains (the `else` binds to covr's `if (TRUE)`), so helpers copied into
the child must be unwrapped first. Functions without instrumentation are
returned unchanged.

## Usage

``` r
strip_coverage(fn)
```

## Arguments

- fn:

  A function.

## Value

`fn`, with covr wrappers removed from its body.
