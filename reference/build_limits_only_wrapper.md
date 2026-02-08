# Build a minimal wrapper script that only applies resource limits

Used when `sandbox = FALSE` but `limits` is provided. Creates a shell
wrapper that sets ulimit values and then `exec`s R.

## Usage

``` r
build_limits_only_wrapper(limits)
```

## Arguments

- limits:

  A named list of resource limits.

## Value

A sandbox config list with `wrapper` and `profile_path = NULL`.
