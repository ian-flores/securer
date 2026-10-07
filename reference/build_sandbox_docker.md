# Build in-container Docker sandbox configuration

Used when the securer session is *already running inside* a Docker
container. The container itself provides filesystem and network
isolation, so this builder skips bubblewrap (which requires namespace
support Docker typically doesn't expose) and applies only resource
limits (`ulimit`) via a wrapper script.

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

This is different from
[`build_sandbox_docker_spawn()`](https://ian-flores.github.io/securer/reference/build_sandbox_docker_spawn.md),
which starts a new container for each child session. This backend is
activated automatically when `/.dockerenv` exists, or manually by
setting `SECURER_SANDBOX_MODE=docker`. The container-spawning backend is
activated by `SECURER_SANDBOX_MODE=docker-spawn`.
