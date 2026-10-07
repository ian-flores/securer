# Default resource limits for sandboxed sessions

Returns the resource limits that
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
and
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
use when `sandbox = TRUE` and you don't pass `limits`. Use it to see the
defaults, or as a starting point for your own.

## Usage

``` r
default_limits()
```

## Value

A named list of resource limits.

## Details

The returned list contains:

- cpu:

  CPU time limit in seconds (default: 60).

- memory:

  Virtual memory limit in bytes (default: 512 MB).

- fsize:

  Maximum file size in bytes (default: 50 MB).

- nproc:

  Maximum number of processes (default: 50).

- nofile:

  Maximum number of open file descriptors (default: 256).

Pass a changed copy to `SecureSession$new(limits = ...)` or
`execute_r(limits = ...)`. Pass `limits = list()` to turn all limits
off.

## Examples

``` r
# Inspect defaults
default_limits()
#> $cpu
#> [1] 60
#> 
#> $memory
#> [1] 536870912
#> 
#> $fsize
#> [1] 52428800
#> 
#> $nproc
#> [1] 50
#> 
#> $nofile
#> [1] 256
#> 

# Double the memory limit
my_limits <- default_limits()
my_limits$memory <- 1024 * 1024 * 1024  # 1 GB
```
