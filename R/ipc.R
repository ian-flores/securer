#' Create a Unix domain socket server
#'
#' @param path Character string, the file path for the socket
#' @return A server connection object from processx
#' @keywords internal
ipc_create_server <- function(path) {
  processx::conn_create_unix_socket(path)
}

#' Accept a client connection on a Unix domain socket server
#'
#' Polls the server connection and accepts the incoming client.
#' Note: `processx::conn_accept_unix_socket()` transitions the server
#' connection itself to "connected_server" state. After calling this,
#' the same `server_conn` object is used for bidirectional data transfer.
#'
#' @param server_conn The server connection returned by [ipc_create_server()]
#' @param timeout Timeout in milliseconds (default 5000)
#' @return Invisible NULL; the server_conn is modified in place
#' @keywords internal
ipc_accept <- function(server_conn, timeout = 5000L) {
  poll_result <- processx::poll(list(server_conn), timeout)
  if (poll_result[[1]] != "connect") {
    stop("Timeout waiting for client connection", call. = FALSE)
  }
  processx::conn_accept_unix_socket(server_conn)
  invisible(NULL)
}

#' Write a message to an IPC connection
#'
#' Serializes a list to JSON and writes it as a single newline-terminated line.
#'
#' @param conn A connection object
#' @param msg A list to serialize and send
#' @keywords internal
ipc_write_message <- function(conn, msg) {
  json <- jsonlite::toJSON(msg, auto_unbox = TRUE)
  processx::conn_write(conn, paste0(json, "\n"))
}

#' Read a message from an IPC connection
#'
#' Reads a single newline-terminated JSON line from the connection, with
#' timeout. Returns parsed list. Raises error on timeout.
#'
#' @param conn A connection object
#' @param timeout Timeout in milliseconds (default 30000)
#' @return A parsed list from the JSON message
#' @keywords internal
ipc_read_message <- function(conn, timeout = 30000L) {
  poll_result <- processx::poll(list(conn), timeout)
  if (poll_result[[1]] != "ready") {
    stop("Timeout waiting for IPC message", call. = FALSE)
  }
  line <- processx::conn_read_lines(conn, n = 1)
  if (length(line) == 0 || !nzchar(line)) {
    stop("Empty message received on IPC connection", call. = FALSE)
  }
  jsonlite::fromJSON(line, simplifyVector = FALSE)
}
