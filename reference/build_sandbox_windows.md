# Build Windows sandbox configuration

True OS-level sandboxing is not available on Windows without admin
privileges (would require Windows Job Objects / AppContainers). This
function raises an error when called, directing users to either use
`sandbox = FALSE` with explicit resource limits, or run inside a
container for real isolation.

## Usage

``` r
build_sandbox_windows(socket_path, r_home)
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

## Value

Never returns; always raises an error.
