# Write a message to an IPC connection

Serializes a list to JSON and writes it as a single newline-terminated
line.

## Usage

``` r
ipc_write_message(conn, msg)
```

## Arguments

- conn:

  A connection object

- msg:

  A list to serialize and send

## Value

Invisible `NULL`; called for its side effect of writing to the
connection.
