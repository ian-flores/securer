# Check R code before running it

Parses the code to catch syntax errors, and looks for calls to functions
that are often risky, such as
[`system()`](https://rdrr.io/r/base/system.html). It's a quick check, so
code that can't run never reaches the child process.

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

  Character vector of warnings about risky-looking calls such as
  [`system()`](https://rdrr.io/r/base/system.html) or
  [`.Internal()`](https://rdrr.io/r/base/Internal.html). Empty if there
  are none. The warnings don't block anything; the sandbox does that.

## Details

The check for risky calls is only advice. It uses simple regular
expressions, so it flags some harmless code and misses some risky code.
What actually restricts files, network, and processes is the OS sandbox
(Seatbelt or bwrap). Don't rely on this check to stop dangerous code.

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

# Warning about a risky call
result <- validate_code("system('ls')")
result$warnings
#> [1] "Code contains call to `system()` which may be restricted by the sandbox"
```
