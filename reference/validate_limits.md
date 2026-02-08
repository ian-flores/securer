# Validate a limits list

Checks that all limit names are recognized and all values are positive
numbers.

## Usage

``` r
validate_limits(limits)
```

## Arguments

- limits:

  A named list of resource limits.

## Value

Invisible `NULL`; raises an error on invalid input.
