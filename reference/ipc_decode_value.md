# Decode a value received over IPC

Reverses
[`ipc_encode_value()`](https://ian-flores.github.io/securer/reference/ipc_encode_value.md).
Only data frames and a fixed set of column classes are rebuilt, so data
from the child can't attach arbitrary classes to objects in the parent.
Malformed encodings are errors.

## Usage

``` r
ipc_decode_value(x)

ipc_decode_data_frame(x)

ipc_decode_column(x)
```

## Arguments

- x:

  A value parsed with `jsonlite::fromJSON(simplifyVector = FALSE)`.

## Value

The decoded value.
