#' Create an audit logger
#'
#' Returns a list of functions that append structured JSONL entries to a file.
#' Each entry includes an ISO 8601 timestamp, event type, and session ID.
#'
#' @param path Character string path for the JSONL audit log file.
#' @param session_id Character string session identifier for correlation.
#' @return A list with a `$log()` method.
#' @noRd
new_audit_logger <- function(path, session_id) {
  # Ensure the parent directory exists
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  log_entry <- function(event, ...) {
    entry <- list(
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
      event = event,
      session_id = session_id
    )
    extra <- list(...)
    if (length(extra) > 0) {
      entry <- c(entry, extra)
    }
    line <- jsonlite::toJSON(entry, auto_unbox = TRUE)
    cat(line, "\n", sep = "", file = path, append = TRUE)
  }

  list(log = log_entry)
}
