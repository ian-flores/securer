# Build Docker sandbox configuration

When running inside a Docker container, the container itself provides
filesystem and network isolation. This builder skips bubblewrap (which
requires namespace support that Docker typically doesn't expose) and
applies only resource limits (`ulimit`) via a wrapper script.

## Usage

``` r
build_sandbox_docker(socket_path, r_home, limits = NULL)
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

## Details

Docker mode is activated automatically when `/.dockerenv` exists, or
manually by setting `SECURER_SANDBOX_MODE=docker`.
