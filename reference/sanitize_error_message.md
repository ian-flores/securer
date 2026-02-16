# Sanitize error messages before returning to LLM

Removes sensitive information from R error messages that could leak host
details to an adversarial LLM. Replaces file paths, hostnames/IPs,
process IDs, and stack traces while preserving the core error type.

## Usage

``` r
sanitize_error_message(msg, max_length = 500L)
```

## Arguments

- msg:

  Character string error message to sanitize.

- max_length:

  Maximum length of the returned message. Defaults to 500.

## Value

A sanitized character string.
