# Default resource limits for sandboxed sessions

Returns the default resource limits that are applied automatically when
`sandbox = TRUE` and no explicit `limits` are provided to
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
or
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md).
Useful for inspecting the defaults and creating custom limits based on
them.

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

  Maximum number of child processes (default: 50).

- nofile:

  Maximum number of open file descriptors (default: 256).

You can pass a modified copy to `SecureSession$new(limits = ...)` or
`execute_r(limits = ...)`. Pass `limits = list()` to explicitly disable
all resource limits.

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
