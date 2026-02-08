# Generate bubblewrap CLI arguments for the sandboxed R session

Creates a character vector of `bwrap` arguments that:

- Isolates all namespaces (PID, net, user, mount, UTS, IPC)

- Bind-mounts system libraries and R read-only

- Provides a clean writable `/tmp` with the UDS socket overlaid

- Blocks all network access via namespace isolation

## Usage

``` r
generate_bwrap_args(socket_path, r_home)
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

## Value

A character vector of bwrap CLI arguments
