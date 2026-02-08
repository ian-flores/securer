# Generate ulimit shell commands from a limits list

Translates a user-facing limits list into shell `ulimit` commands that
can be injected into wrapper scripts before the `exec` line.

## Usage

``` r
generate_ulimit_commands(limits)
```

## Arguments

- limits:

  A named list of resource limits, or `NULL` for no limits.

## Value

A character vector of shell commands (one per limit), or `character(0)`
if `limits` is `NULL` or empty.

## Details

Supported limit names:

- cpu:

  CPU time in seconds (`ulimit -t`)

- memory:

  Virtual memory (address space) in bytes (`ulimit -v`). Converted to
  kilobytes for ulimit.

- fsize:

  Maximum file size in bytes (`ulimit -f`). Converted to 512-byte blocks
  for ulimit.

- nproc:

  Maximum number of processes (`ulimit -u`)

- nofile:

  Maximum number of open files (`ulimit -n`)

- stack:

  Maximum stack size in bytes (`ulimit -s`). Converted to kilobytes for
  ulimit.
