# Write a message to an IPC connection

Serializes a list to JSON and writes it as a single newline-terminated
line, looping until all of it is written.

## Usage

``` r
ipc_write_message(conn, msg, timeout = 30000L)
```

## Arguments

- conn:

  A connection object

- msg:

  A list to serialize and send

- timeout:

  Timeout in milliseconds (default 30000)

## Value

Invisible `NULL`; called for its side effect of writing to the
connection.
