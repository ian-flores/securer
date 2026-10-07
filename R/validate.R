#' Check R code before running it
#'
#' Parses the code to catch syntax errors, and looks for calls to functions
#' that are often risky, such as `system()`. It's a quick check, so code that
#' can't run never reaches the child process.
#'
#' The check for risky calls is only advice. It uses simple regular
#' expressions, so it flags some harmless code and misses some risky code.
#' What actually restricts files, network, and processes is the OS sandbox
#' (Seatbelt or bwrap). Don't rely on this check to stop dangerous code.
#'
#' @param code Character string of R code to validate.
#' @return A list with components:
#'   \describe{
#'     \item{valid}{Logical. `TRUE` if the code parses without error.}
#'     \item{error}{`NULL` on success, or a character string describing the
#'       parse error.}
#'     \item{warnings}{Character vector of warnings about risky-looking calls
#'       such as `system()` or `.Internal()`. Empty if there are none. The
#'       warnings don't block anything; the sandbox does that.}
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
#' # Warning about a risky call
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
