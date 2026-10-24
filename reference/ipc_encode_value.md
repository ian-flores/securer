# Encode a value for IPC

Plain JSON turns a data frame into a list of rows and drops column
types, factor levels and classes. This tags data frames (recursively,
inside plain lists) so
[`ipc_decode_value()`](https://ian-flores.github.io/securer/reference/ipc_decode_value.md)
can rebuild them exactly. Other values are left for jsonlite to encode
as before.

## Usage

``` r
ipc_encode_value(x)
```

## Arguments

- x:

  A value to send.

## Value

A JSON-ready value.
