# Generate type validation code for tool arguments

Produces R code as a character string that checks each argument's type
against its declared type annotation. Arguments without type annotations
are skipped.

## Usage

``` r
generate_type_checks(tool_name, args)
```

## Arguments

- tool_name:

  Character, the tool name (for error messages)

- args:

  Named list mapping argument names to type strings

## Value

Character string of R code performing type checks (may be empty)
