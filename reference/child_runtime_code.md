# Generate the R code to inject into the child process

Returns a character string of R code that, when evaluated in the child
process, sets up the IPC connection and defines `.securer_call_tool()`.

## Usage

``` r
child_runtime_code()
```

## Value

A single character string of R code
