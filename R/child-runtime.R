#' Generate the R code to inject into the child process
#'
#' Returns a character string of R code that, when evaluated in the child
#' process, sets up the IPC connection and defines `.securer_call_tool()`.
#'
#' @param max_message_size Largest IPC message, in bytes, the child will
#'   send or accept.
#' @return A single character string of R code
#' @keywords internal
child_runtime_code <- function(max_message_size = ipc_max_message_size) {
  # The IPC framing and encoding helpers from R/ipc.R are copied into the
  # child, so both ends of the socket share one implementation.
  helpers <- c(
    "ipc_encode_value", "ipc_encode_column", "ipc_decode_value",
    "ipc_decode_data_frame", "ipc_decode_column", "ipc_to_json",
    "ipc_write_line", "ipc_poll_line"
  )
  helper_code <- vapply(helpers, function(nm) {
    paste0(nm, " <- ", paste(deparse(get(nm)), collapse = "\n"))
  }, character(1))
  # Splice with strsplit() rather than sub(), which would treat
  # backslashes in the deparsed code as escapes.
  parts <- strsplit(child_runtime_template, "%HELPERS%", fixed = TRUE)[[1]]
  code <- paste0(parts[1], paste(helper_code, collapse = "\n"), parts[2])
  parts <- strsplit(code, "%MAX_SIZE%", fixed = TRUE)[[1]]
  paste0(parts[1], format(as.integer(max_message_size)), parts[2])
}

child_runtime_template <- '
  .securer_call_tool <- local({
    %HELPERS%
    .max_size <- %MAX_SIZE%

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

    .buffer <- new.env(parent = emptyenv())

    function(tool_name, ...) {
      c <- .get_conn()
      args <- list(...)
      request <- ipc_to_json(
        list(type = "tool_call", tool = tool_name, args = args)
      )
      size <- nchar(request, type = "bytes")
      if (size > .max_size) {
        stop("Tool call arguments too large to send over IPC (", size,
             " bytes, max ", .max_size, ")", call. = FALSE)
      }
      ipc_write_line(c, request)

      response_raw <- ipc_poll_line(c, .buffer, 30000, .max_size)
      if (is.null(response_raw)) {
        stop("No response to tool call ", sQuote(tool_name),
             " from the parent process", call. = FALSE)
      }
      result <- ipc_decode_value(
        jsonlite::fromJSON(response_raw, simplifyVector = FALSE)
      )
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
