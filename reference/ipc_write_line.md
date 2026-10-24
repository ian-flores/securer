# Write one line to an IPC connection

[`processx::conn_write()`](http://processx.r-lib.org/reference/processx_connections.md)
writes only as much as the socket buffer takes (about 8 KB on macOS) and
returns the rest. This keeps writing until the whole line is sent.

## Usage

``` r
ipc_write_line(conn, line, timeout = 30000L)
```

## Arguments

- conn:

  A connection object

- line:

  A string, without the trailing newline

- timeout:

  Timeout in milliseconds

## Value

Invisible `NULL`.
