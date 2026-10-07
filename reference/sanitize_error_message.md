# Clean error messages before they go back to an LLM

Removes details from R error messages that would tell a hostile LLM
about the host. Replaces file paths, hostnames/IPs, process IDs, and
stack traces while preserving the core error type.

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
