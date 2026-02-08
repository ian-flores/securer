# Accept a client connection on a Unix domain socket server

Polls the server connection and accepts the incoming client. Note:
[`processx::conn_accept_unix_socket()`](http://processx.r-lib.org/reference/processx_sockets.md)
transitions the server connection itself to "connected_server" state.
After calling this, the same `server_conn` object is used for
bidirectional data transfer.

## Usage

``` r
ipc_accept(server_conn, timeout = 5000L)
```

## Arguments

- server_conn:

  The server connection returned by
  [`ipc_create_server()`](https://ian-flores.github.io/securer/reference/ipc_create_server.md)

- timeout:

  Timeout in milliseconds (default 5000)

## Value

Invisible NULL; the server_conn is modified in place
