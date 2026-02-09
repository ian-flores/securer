#' Generate the R code to inject into the child process
#'
#' Returns a character string of R code that, when evaluated in the child
#' process, sets up the IPC connection and defines `.securer_call_tool()`.
#'
#' @return A single character string of R code
#' @keywords internal
child_runtime_code <- function() {
  '
  .securer_env <- new.env(parent = emptyenv())
  .securer_env$socket_path <- Sys.getenv("SECURER_SOCKET")
  .securer_env$conn <- NULL

  .securer_connect <- function() {
    .securer_env$conn <- processx::conn_connect_unix_socket(
      .securer_env$socket_path
    )
  }

  .securer_call_tool <- function(tool_name, ...) {
    args <- list(...)
    request <- jsonlite::toJSON(
      list(type = "tool_call", tool = tool_name, args = args),
      auto_unbox = TRUE
    )
    processx::conn_write(.securer_env$conn, paste0(request, "\\n"))

    # Poll then read
    processx::poll(list(.securer_env$conn), 30000)
    response_raw <- processx::conn_read_lines(.securer_env$conn, n = 1)
    result <- jsonlite::fromJSON(response_raw, simplifyVector = FALSE)
    if (!is.null(result$error)) stop(result$error, call. = FALSE)
    result$value
  }

  .securer_connect()

  # Send authentication token to the parent as the first message.
  # The parent validates this before accepting any tool calls.
  processx::conn_write(
    .securer_env$conn,
    paste0(Sys.getenv("SECURER_TOKEN"), "\\n")
  )

  lockEnvironment(.securer_env, bindings = TRUE)
  lockBinding(".securer_call_tool", globalenv())
  lockBinding(".securer_connect", globalenv())
  lockBinding(".securer_env", globalenv())
  '
}
