# Build Windows sandbox configuration

Provides environment-variable-only isolation for Windows. Windows lacks
an unprivileged lightweight sandbox comparable to macOS Seatbelt or
Linux bubblewrap, so this implementation sets restrictive environment
variables to limit the child R process. Specifically:

- Sets `R_LIBS_USER` to empty, preventing user-installed packages

- Sets `HOME` and `TMPDIR` to a clean temporary directory

- Sets `R_USER` to match the clean temp directory

- Clears `R_ENVIRON_USER` and `R_PROFILE_USER` to prevent user startup
  code from executing

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

A sandbox config list with:

- wrapper:

  `NULL` (no wrapper script on Windows)

- profile_path:

  `NULL` (no sandbox profile on Windows)

- env:

  Named character vector of restrictive environment variables to pass to
  [`callr::r_session_options()`](https://callr.r-lib.org/reference/r_session_options.html)

## Details

**Important:** This does NOT enforce filesystem or network restrictions.
Any code running in the child process can still access the filesystem
and network without restriction. For true sandboxing on Windows, admin
privileges and Windows Job Objects / AppContainers would be required.
