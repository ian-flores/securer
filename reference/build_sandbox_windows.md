# Build Windows sandbox configuration

Provides environment isolation and optional resource limits via Windows
Job Objects. Environment isolation creates a sanitized set of
environment variables with clean HOME, TMPDIR, TMP, TEMP pointing to a
private temp directory, and an empty R_LIBS_USER.

## Usage

``` r
build_sandbox_windows(socket_path, r_home, limits = NULL)
```

## Arguments

- socket_path:

  Path to the UDS socket

- r_home:

  Path to the R installation

- limits:

  Optional named list of resource limits. Supported on Windows via Job
  Objects: `cpu`, `memory`, `nproc`. Unsupported (will warn): `fsize`,
  `nofile`, `stack`.

## Value

A list with elements:

- wrapper:

  Always `NULL` on Windows (no wrapper script)

- profile_path:

  Always `NULL` on Windows

- env:

  A named character vector of sanitized environment variables

- sandbox_tmp:

  Path to the private temp directory

- apply_limits:

  A function taking a PID to apply Job Object limits, or `NULL` if no
  supported limits were requested

## Details

When resource limits are provided (cpu, memory, nproc), a PowerShell
script using C# P/Invoke is generated to create a Job Object with the
specified constraints and assign the child process to it. Limits that
have no Job Object equivalent (fsize, nofile, stack) emit a warning and
are skipped.
