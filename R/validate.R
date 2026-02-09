#' Validate R code before execution
#'
#' Parses the code string to catch syntax errors and optionally checks for
#' potentially dangerous function calls.  This is intended as a fast pre-check
#' so that obviously broken code never reaches the child process.
#'
#' **Note:** Pattern-based validation is ADVISORY ONLY.  It uses simple regex
#' matching and can produce both false positives and false negatives.
#' The OS-level sandbox (Seatbelt / bwrap) is the actual enforcement layer
#' that restricts filesystem, network, and process access.  Do not rely on
#' validation alone to prevent dangerous operations.
#'
#' @param code Character string of R code to validate.
#' @return A list with components:
#'   \describe{
#'     \item{valid}{Logical. `TRUE` if the code parses without error.}
#'     \item{error}{`NULL` on success, or a character string describing the
#'       parse error.}
#'     \item{warnings}{Character vector of advisory warnings about potentially
#'       dangerous patterns (e.g. `system()`, `.Internal()`).  Empty if none
#'       detected.  These are advisory only --- the sandbox handles actual
#'       restriction.}
#'   }
#'
#' @examples
#' # Valid code
#' result <- validate_code("1 + 1")
#' result$valid
#' # TRUE
#'
#' # Syntax error
#' result <- validate_code("if (TRUE {")
#' result$valid
#' # FALSE
#' result$error
#'
#' # Dangerous pattern warning
#' result <- validate_code("system('ls')")
#' result$warnings
#'
#' @export
validate_code <- function(code) {
  if (!is.character(code) || length(code) != 1) {
    stop("`code` must be a single character string", call. = FALSE)
  }

  # Try parsing
  parsed <- tryCatch(
    parse(text = code),
    error = function(e) e
  )

  if (inherits(parsed, "error")) {
    return(list(
      valid = FALSE,
      error = conditionMessage(parsed),
      warnings = character(0)
    ))
  }

  # Check for dangerous patterns (ADVISORY ONLY — sandbox handles enforcement)
  dangerous <- c(
    # Shell / process execution
    "system", "system2", "shell",
    # R internals
    ".Internal", "Sys.setenv",
    # Native code interface
    ".Call", ".C", ".Fortran", ".External",
    # Shared library loading
    "dyn.load",
    # Shell pipe
    "pipe",
    # Subprocess execution via packages
    "processx::run", "callr::r",
    # Network connections
    "socketConnection", "url",
    # Indirect invocation (advisory)
    "do.call"
  )
  warnings <- character(0)
  for (pattern in dangerous) {
    # Use fixed matching for function-call-like patterns
    escaped <- gsub("\\.", "\\\\.", pattern)
    # For namespaced patterns like processx::run, anchor on :: not \b
    if (grepl("::", pattern)) {
      regex <- paste0(escaped, "\\s*\\(")
    } else {
      regex <- paste0("\\b", escaped, "\\s*\\(")
    }
    if (grepl(regex, code)) {
      warnings <- c(warnings, paste0(
        "Code contains call to `", pattern, "()` which may be restricted by the sandbox"
      ))
    }
  }

  list(
    valid = TRUE,
    error = NULL,
    warnings = warnings
  )
}
