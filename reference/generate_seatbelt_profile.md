# Generate a macOS Seatbelt profile for the sandboxed R session

Creates a Seatbelt policy string that:

- Denies all operations by default

- Allows file reads only for R installation, library paths, system
  libraries, and temp directories (blocks ~/.ssh, ~/.env, etc.)

- Allows file writes only to the temp directory (for UDS + R temp files)

- Allows Unix domain socket operations (IPC with the parent)

- Denies remote network access (TCP/UDP)

- Allows only process-fork and process-exec for the R binary

- Allows only specific system operations R needs

## Usage

``` r
generate_seatbelt_profile(socket_path, r_home, lib_paths = .libPaths())
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

- lib_paths:

  Character vector of R library paths (default:
  [`.libPaths()`](https://rdrr.io/r/base/libPaths.html))

## Value

A single character string containing the Seatbelt profile
