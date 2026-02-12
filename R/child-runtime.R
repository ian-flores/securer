#' Generate the R code to inject into the child process
#'
#' Returns a character string of R code that, when evaluated in the child
#' process, sets up the IPC connection and defines `.securer_call_tool()`.
#'
#' @return A single character string of R code
#' @keywords internal
child_runtime_code <- function() {
  '
  .securer_call_tool <- local({
    socket_path <- Sys.getenv("SECURER_SOCKET")
    conn <- processx::conn_connect_unix_socket(socket_path)

    # Send authentication token to the parent as the first message.
    # The parent validates this before accepting any tool calls.
    processx::conn_write(
      conn,
      paste0(Sys.getenv("SECURER_TOKEN"), "\\n")
    )

    # Clear sensitive env vars so child code cannot read them
    Sys.unsetenv("SECURER_TOKEN")
    Sys.unsetenv("SECURER_SOCKET")

    function(tool_name, ...) {
      args <- list(...)
      request <- jsonlite::toJSON(
        list(type = "tool_call", tool = tool_name, args = args),
        auto_unbox = TRUE
      )
      processx::conn_write(conn, paste0(request, "\\n"))

      # Poll then read
      processx::poll(list(conn), 30000)
      response_raw <- processx::conn_read_lines(conn, n = 1)
      result <- jsonlite::fromJSON(response_raw, simplifyVector = FALSE)
      if (!is.null(result$error)) stop(result$error, call. = FALSE)
      result$value
    }
  })

  lockBinding(".securer_call_tool", globalenv())

  # Shadow unlockBinding to prevent child code from unlocking our bindings
  unlockBinding <- function(...) {
    stop("unlockBinding is not permitted in secure sessions", call. = FALSE)
  }
  lockBinding("unlockBinding", globalenv())
  '
}
