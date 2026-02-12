#' Sanitize error messages before returning to LLM
#'
#' Removes sensitive information from R error messages that could leak
#' host details to an adversarial LLM. Replaces file paths, hostnames/IPs,
#' process IDs, and stack traces while preserving the core error type.
#'
#' @param msg Character string error message to sanitize.
#' @param max_length Maximum length of the returned message. Defaults to 500.
#' @return A sanitized character string.
#' @keywords internal
sanitize_error_message <- function(msg, max_length = 500L) {
  if (!is.character(msg) || length(msg) == 0) return("Unknown error")
  msg <- msg[1]

  # Strip stack traces: remove "Call stack:", "Traceback:", or "Stack trace:"
  # sections and everything after them
  msg <- sub(
    "(?s)(Traceback|Call stack|Stack trace):?\\s*\\n.*", "",
    msg, perl = TRUE
  )

  # Replace absolute file paths:
  #   Unix: /Users/..., /home/..., /tmp/..., /var/..., /etc/..., /opt/...
  #   Windows: C:\..., D:\...
  msg <- gsub(
    "(/Users|/home|/tmp|/var|/etc|/opt)/[^ '\",:)}\n]+",
    "[path]", msg
  )
  msg <- gsub("[A-Z]:\\\\[^ '\",:)}\n]+", "[path]", msg)

  # Replace process IDs:
  #   "process '12345'", "process 12345", "PID 12345", "pid: 12345"
  msg <- gsub(
    "process\\s*'\\d+'", "process '[pid]'",
    msg, ignore.case = TRUE
  )
  msg <- gsub(
    "process\\s+(\\d{2,})", "process [pid]",
    msg, ignore.case = TRUE
  )
  msg <- gsub(
    "PID\\s*:?\\s*\\d+", "PID [pid]",
    msg, ignore.case = TRUE
  )

  # Replace hostnames/IPs in connection error contexts
  # IPv4 addresses (with optional port)
  msg <- gsub(
    "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}(:\\d+)?",
    "[host]", msg
  )
  # Hostname patterns in connection-related messages
  msg <- gsub(
    paste0(
      "((?:connect|resolve|host|server|connection)\\s+(?:to\\s+)?",
      "['\"]?)([a-zA-Z0-9][-a-zA-Z0-9.]*\\.[a-zA-Z]{2,})(:\\d+)?"
    ),
    "\\1[host]", msg, perl = TRUE, ignore.case = TRUE
  )

  # Truncate to max_length
  if (nchar(msg) > max_length) {
    msg <- paste0(substr(msg, 1, max_length - 3), "...")
  }

  msg
}


#' Create an ellmer tool for secure R code execution
#'
#' Wraps a [SecureSession] as an [ellmer::tool()] definition so an LLM can
#' execute R code in a sandboxed environment. The tool accepts a single
#' `code` argument (a string of R code) and returns the result.
#'
#' @param session A [SecureSession] object. If `NULL` (the default), a
#'   new session is created with the given `tools`, `sandbox`, and `limits`
#'   arguments. When you supply your own session, those arguments are
#'   ignored.
#' @param tools A list of [securer_tool()] objects to register in the
#'   session. Only used when `session` is `NULL`.
#' @param sandbox Logical, whether to enable OS-level sandboxing.
#'   Only used when `session` is `NULL`. Defaults to `TRUE`.
#' @param limits Optional named list of resource limits.
#'   Only used when `session` is `NULL`.
#' @param timeout Timeout in seconds for each code execution, or `NULL`
#'   for no timeout. Defaults to 30.
#'
#' @return An ellmer `ToolDef` object that can be registered with
#'   `chat$register_tool()`.
#'
#' @examples
#' \dontrun{
#' library(ellmer)
#'
#' # Basic usage: LLM can execute R code in a sandbox
#' chat <- chat_openai()
#' chat$register_tool(securer_as_ellmer_tool())
#' chat$chat("What is the mean of the numbers 1 through 100?")
#'
#' # With custom tools available inside the sandbox
#' tools <- list(
#'   securer_tool("fetch_data", "Fetch a dataset by name",
#'     fn = function(name) get(name, "package:datasets"),
#'     args = list(name = "character"))
#' )
#' chat$register_tool(securer_as_ellmer_tool(tools = tools))
#' chat$chat("Load the mtcars dataset and compute the mean mpg.")
#'
#' # With a pre-existing session
#' session <- SecureSession$new(sandbox = TRUE)
#' chat$register_tool(securer_as_ellmer_tool(session = session))
#' # ... use chat ...
#' session$close()
#' }
#'
#' @export
securer_as_ellmer_tool <- function(session = NULL,
                                   tools = list(),
                                   sandbox = TRUE,
                                   limits = NULL,
                                   timeout = 30) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop(
      "Package 'ellmer' is required for securer_as_ellmer_tool(). ",
      "Install it with: install.packages('ellmer')",
      call. = FALSE
    )
  }

  # Create a session if one wasn't provided
  owns_session <- is.null(session)
  if (owns_session) {
    session <- SecureSession$new(
      tools = tools,
      sandbox = sandbox,
      limits = limits
    )
    # Ensure the session is cleaned up when the enclosing environment
    # (and thus the tool closure) is garbage collected.
    reg.finalizer(session$.__enclos_env__, function(e) {
      try(e$self$close(), silent = TRUE)
    }, onexit = TRUE)
  }

  # Build the executor function.
  # We capture `session` and `timeout` in the closure.
  execute_fn <- function(code) {
    if (!session$is_alive()) {
      return(ellmer::ContentToolResult(
        error = "SecureSession is no longer alive. Create a new tool with securer_as_ellmer_tool()."
      ))
    }
    tryCatch(
      {
        result <- session$execute(code, timeout = timeout)
        format_tool_result(result)
      },
      error = function(e) {
        ellmer::ContentToolResult(
          error = sanitize_error_message(conditionMessage(e))
        )
      }
    )
  }

  ellmer::tool(
    execute_fn,
    name = "execute_r_code",
    description = paste0(
      "Execute R code in a secure sandboxed environment. ",
      "The code is run in an isolated R process with restricted ",
      "file system and network access. ",
      "Pass a single string of valid R code. ",
      "The result of the last expression is returned."
    ),
    arguments = list(
      code = ellmer::type_string(
        "A string containing valid R code to execute."
      )
    )
  )
}


#' Format an R value as a tool result string
#'
#' Converts R objects into a human-readable string suitable for returning
#' to an LLM as a tool result. Data frames get a truncated print
#' representation; scalars are coerced directly; other objects use
#' `capture.output(print(...))`.
#'
#' @param value Any R object returned by code execution.
#' @return A character string.
#' @keywords internal
format_tool_result <- function(value) {
  if (is.null(value)) {
    return("NULL")
  }
  if (is.atomic(value) && length(value) == 1) {
    return(as.character(value))
  }
  # For data frames, show a compact representation
  if (is.data.frame(value)) {
    lines <- utils::capture.output(print(value, max = 50))
    if (length(lines) > 30) {
      lines <- c(utils::head(lines, 30), sprintf("... (%d rows total)", nrow(value)))
    }
    return(paste(lines, collapse = "\n"))
  }
  # General case
  lines <- utils::capture.output(print(value))
  if (length(lines) > 50) {
    lines <- c(utils::head(lines, 50), "... (output truncated)")
  }
  paste(lines, collapse = "\n")
}
