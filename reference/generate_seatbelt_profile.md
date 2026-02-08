# Generate a macOS Seatbelt profile for the sandboxed R session

Creates a Seatbelt policy string that:

- Denies all operations by default

- Allows file reads everywhere (low risk, needed for R + packages)

- Allows file writes only to the temp directory (for UDS + R temp files)

- Allows Unix domain socket operations (IPC with the parent)

- Denies remote network access (TCP/UDP)

- Allows process, mach, sysctl, and signal operations needed by R

## Usage

``` r
generate_seatbelt_profile(socket_path, r_home)
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

## Value

A single character string containing the Seatbelt profile
