# Read a message from an IPC connection

Reads a single newline-terminated JSON line from the connection, with
timeout. Returns parsed list. Raises error on timeout.

## Usage

``` r
ipc_read_message(conn, timeout = 30000L)
```

## Arguments

- conn:

  A connection object

- timeout:

  Timeout in milliseconds (default 30000)

## Value

A parsed list from the JSON message
