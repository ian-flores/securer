# Build macOS sandbox configuration

Writes a temporary Seatbelt profile and creates a wrapper shell script
that launches R inside `sandbox-exec`. The wrapper can be passed to
[`callr::r_session_options()`](https://callr.r-lib.org/reference/r_session_options.html)
via the `arch` parameter (which callr uses as the path to the R binary).

## Usage

``` r
build_sandbox_macos(socket_path, r_home, limits = NULL)
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

- limits:

  Optional named list of resource limits (see
  [`generate_ulimit_commands()`](https://ian-flores.github.io/securer/reference/generate_ulimit_commands.md))

## Value

A sandbox config list (see
[`build_sandbox_config()`](https://ian-flores.github.io/securer/reference/build_sandbox_config.md))
