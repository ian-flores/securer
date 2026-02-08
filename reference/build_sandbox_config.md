# Build sandbox configuration for the current platform

Inspects the operating system and delegates to the appropriate platform-
specific sandbox builder. Returns a list that `start_session()` uses to
wrap the child R process.

## Usage

``` r
build_sandbox_config(socket_path, r_home = R.home(), limits = NULL)
```

## Arguments

- socket_path:

  Path to the UDS socket (must be writable by the child)

- r_home:

  Path to the R installation (default:
  [`R.home()`](https://rdrr.io/r/base/Rhome.html))

- limits:

  Optional named list of resource limits (see
  [`generate_ulimit_commands()`](https://ian-flores.github.io/securer/reference/generate_ulimit_commands.md))

## Value

A list with elements:

- wrapper:

  Path to a shell wrapper script, or `NULL`

- profile_path:

  Path to the generated sandbox profile, or `NULL`
