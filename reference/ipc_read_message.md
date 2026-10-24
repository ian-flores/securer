# Read a message from an IPC connection

Reads a single newline-terminated JSON line from the connection, with
timeout. Returns parsed list. Raises error on timeout.

## Usage

``` r
ipc_read_message(
  conn,
  timeout = 30000L,
  max_size = ipc_max_message_size,
  buffer = new.env(parent = emptyenv())
)
```

## Arguments

- conn:

  A connection object

- timeout:

  Timeout in milliseconds (default 30000)

- max_size:

  Largest message allowed, in bytes

- buffer:

  Environment holding unread data for `conn`. Pass the same one on every
  read from a connection so partial data isn't lost.

## Value

A parsed list from the JSON message
