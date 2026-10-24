# Generate the R code to inject into the child process

Returns a character string of R code that, when evaluated in the child
process, sets up the IPC connection and defines `.securer_call_tool()`.

## Usage

``` r
child_runtime_code(max_message_size = ipc_max_message_size)
```

## Arguments

- max_message_size:

  Largest IPC message, in bytes, the child will send or accept.

## Value

A single character string of R code
