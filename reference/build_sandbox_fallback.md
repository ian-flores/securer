# Build fallback sandbox configuration (no OS sandbox)

Used when no platform-specific sandbox is available. Returns a config
with `NULL` wrapper and profile so the session starts without any
OS-level isolation.

## Usage

``` r
build_sandbox_fallback(socket_path, r_home)
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

## Value

A sandbox config list with `wrapper = NULL` and `profile_path = NULL`
