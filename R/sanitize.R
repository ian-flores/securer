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
