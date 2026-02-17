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
    .conn <- processx::conn_connect_unix_socket(socket_path)

    # Send authentication token to the parent as the first message.
    # The parent validates this before accepting any tool calls.
    processx::conn_write(
      .conn,
      paste0(Sys.getenv("SECURER_TOKEN"), "\\n")
    )

    # Clear sensitive env vars so child code cannot read them
    Sys.unsetenv("SECURER_TOKEN")
    Sys.unsetenv("SECURER_SOCKET")

    # Store the connection in a sealed environment so that
    # environment(.securer_call_tool)$conn (or $.conn) cannot
    # trivially extract the live UDS connection object.
    # The .ipc_store environment has a custom $ method that blocks
    # direct access, and is locked to prevent modification.
    .ipc_store <- new.env(parent = emptyenv())
    .ipc_store$.c <- .conn
    .ipc_store[["$"]] <- function(x, name) {
      stop("access denied", call. = FALSE)
    }
    lockEnvironment(.ipc_store)
    rm(.conn)

    # The accessor is a local function, not exported into the closure
    # environment directly. Only .securer_call_tool can use it.
    .get_conn <- function() .ipc_store[[".c"]]

    function(tool_name, ...) {
      c <- .get_conn()
      args <- list(...)
      request <- jsonlite::toJSON(
        list(type = "tool_call", tool = tool_name, args = args),
        auto_unbox = TRUE
      )
      processx::conn_write(c, paste0(request, "\\n"))

      # Poll then read
      processx::poll(list(c), 30000)
      response_raw <- processx::conn_read_lines(c, n = 1)
      result <- jsonlite::fromJSON(response_raw, simplifyVector = FALSE)
      if (!is.null(result$error)) stop(result$error, call. = FALSE)
      result$value
    }
  })

  lockBinding(".securer_call_tool", globalenv())

  # Shadow unlockBinding to prevent child code from unlocking our bindings.
  # This covers both bare unlockBinding() and base::unlockBinding() calls.
  # Note: even if an attacker manages to bypass this shadow (e.g. via
  # getFromNamespace), parent-side validation of the IPC token and tool
  # registry provides the authoritative security boundary (defense-in-depth).
  unlockBinding <- function(...) {
    stop("unlockBinding is not permitted in secure sessions", call. = FALSE)
  }
  lockBinding("unlockBinding", globalenv())

  # Also block the base:: namespace path. assignInNamespace may fail if
  # the base namespace is sealed, so we wrap in tryCatch. Even if this
  # fails, the parent-side validation is the real security layer.
  tryCatch(
    assignInNamespace("unlockBinding", function(...) {
      stop("unlockBinding is not permitted in secure sessions", call. = FALSE)
    }, "base"),
    error = function(e) NULL
  )

  # Block common bypass routes for accessing base::unlockBinding.
  # These are defense-in-depth; parent-side IPC validation is authoritative.
  makeActiveBinding("getFromNamespace", function() {
    stop("getFromNamespace is not permitted in secure sessions", call. = FALSE)
  }, globalenv())
  lockBinding("getFromNamespace", globalenv())

  makeActiveBinding("getNativeSymbolInfo", function() {
    stop("getNativeSymbolInfo is not permitted in secure sessions", call. = FALSE)
  }, globalenv())
  lockBinding("getNativeSymbolInfo", globalenv())
  '
}
