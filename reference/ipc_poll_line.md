# Read one line from an IPC connection, if one arrives in time

A message bigger than the socket buffer arrives in pieces. The pieces
are kept in `buffer` (an environment, one per connection) until a full
line is in. Reading stops with an error as soon as the pending data
passes `max_size`, before the rest is pulled into memory.

## Usage

``` r
ipc_poll_line(conn, buffer, timeout, max_size = ipc_max_message_size)
```

## Arguments

- conn:

  A connection object

- buffer:

  An environment holding this connection's unread data

- timeout:

  Timeout in milliseconds

- max_size:

  Largest message allowed, in bytes

## Value

The line, or `NULL` if none completed in time or the connection was
closed (then `buffer$closed` is `TRUE`).
