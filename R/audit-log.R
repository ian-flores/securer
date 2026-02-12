#' Validate an audit log path
#'
#' Checks the proposed audit log file path for security issues:
#' symlinks, device files, and path traversal. Called by
#' `new_audit_logger()` before any data is written.
#'
#' @param path Character string file path to validate.
#' @return Invisibly returns `TRUE` on success; errors on failure.
#' @noRd
validate_audit_log_path <- function(path) {
  if (!is.character(path) || length(path) != 1 || nchar(path) == 0) {
    stop("audit_log path must be a non-empty character string", call. = FALSE)
  }

  # Resolve the parent directory to catch traversal tricks
  resolved_dir <- normalizePath(dirname(path), mustWork = FALSE)

  # Block device files (/dev/*)
  if (grepl("^/dev(/|$)", resolved_dir)) {
    stop("audit_log path must not point to a device file", call. = FALSE)
  }

  resolved_path <- file.path(resolved_dir, basename(path))
  if (grepl("^/dev(/|$)", resolved_path)) {
    stop("audit_log path must not point to a device file", call. = FALSE)
  }

  # If the file already exists, check it's not a symlink
  if (file.exists(path)) {
    link_target <- Sys.readlink(path)
    if (!is.na(link_target) && nchar(link_target) > 0) {
      stop("audit_log path must not be a symlink", call. = FALSE)
    }
  }

  invisible(TRUE)
}


#' Create an audit logger
#'
#' Returns a list of functions that append structured JSONL entries to a file.
#' Each entry includes an ISO 8601 timestamp, event type, and session ID.
#'
#' @param path Character string path for the JSONL audit log file.
#' @param session_id Character string session identifier for correlation.
#' @param max_code_length Maximum length of the `code` field in log entries.
#'   Code longer than this is truncated. Defaults to 10000.
#' @return A list with a `$log()` method.
#' @noRd
new_audit_logger <- function(path, session_id, max_code_length = 10000L) {
  # Validate the path before doing anything
  validate_audit_log_path(path)

  # Ensure the parent directory exists
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  log_entry <- function(event, ...) {
    entry <- list(
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
      event = event,
      session_id = session_id
    )
    extra <- list(...)
    # Truncate the code field if present and too long
    if (!is.null(extra$code) && is.character(extra$code) &&
        nchar(extra$code) > max_code_length) {
      extra$code <- paste0(
        substr(extra$code, 1, max_code_length),
        "... [truncated]"
      )
    }
    if (length(extra) > 0) {
      entry <- c(entry, extra)
    }
    line <- jsonlite::toJSON(entry, auto_unbox = TRUE)
    cat(line, "\n", sep = "", file = path, append = TRUE)
  }

  list(log = log_entry)
}
