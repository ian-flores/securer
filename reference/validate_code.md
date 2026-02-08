# Validate R code before execution

Parses the code string to catch syntax errors and optionally checks for
potentially dangerous function calls. This is intended as a fast
pre-check so that obviously broken code never reaches the child process.

## Usage

``` r
validate_code(code)
```

## Arguments

- code:

  Character string of R code to validate.

## Value

A list with components:

- valid:

  Logical. `TRUE` if the code parses without error.

- error:

  `NULL` on success, or a character string describing the parse error.

- warnings:

  Character vector of warnings about potentially dangerous patterns
  (e.g. [`system()`](https://rdrr.io/r/base/system.html),
  [`.Internal()`](https://rdrr.io/r/base/Internal.html)). Empty if none
  detected. These are advisory only — the sandbox handles actual
  restriction.

## Examples

``` r
# Valid code
result <- validate_code("1 + 1")
result$valid
#> [1] TRUE
# TRUE

# Syntax error
result <- validate_code("if (TRUE {")
result$valid
#> [1] FALSE
# FALSE
result$error
#> [1] "<text>:1:10: unexpected '{'\n1: if (TRUE {\n             ^"

# Dangerous pattern warning
result <- validate_code("system('ls')")
result$warnings
#> [1] "Code contains call to `system()` which may be restricted by the sandbox"
```
