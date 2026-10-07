# Build Docker container-spawning sandbox configuration

Spawns the child R process inside a fresh Docker container instead of
running it natively. The wrapper script invokes `docker run` with
`--network=none`, memory/CPU caps, and a bind mount of the UDS socket
directory so the child can connect back to the parent. It isolates the
child more than the in-Docker backend (which assumes the session itself
is already inside a container), but each session waits for a container
to start.

## Usage

``` r
build_sandbox_docker_spawn(socket_path, r_home, limits = NULL)
```

## Arguments

- socket_path:

  Path to the UDS socket (must live in the mount dir)

- r_home:

  Path to the R installation (unused; R comes from the container image)

- limits:

  Optional named list of resource limits. `memory` and `cpu` are mapped
  to docker flags; other keys become ulimit commands applied inside the
  container.

## Value

A sandbox config list (see
[`build_sandbox_config()`](https://ian-flores.github.io/securer/reference/build_sandbox_config.md))

## Details

Activated by setting `SECURER_SANDBOX_MODE=docker-spawn`. The image
defaults to `rocker/r-base:latest` but can be overridden via
`SECURER_DOCKER_IMAGE`. The bind-mount directory defaults to the socket
path's parent directory (usually `/tmp`) and can be overridden via
`SECURER_DOCKER_MOUNT`.

The backend gates at runtime on `docker --version`; if docker is not
available the dispatcher in
[`build_sandbox_config()`](https://ian-flores.github.io/securer/reference/build_sandbox_config.md)
falls through to the next backend.
