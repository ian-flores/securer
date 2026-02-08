#' Validate R code before execution
#'
#' Parses the code string to catch syntax errors and optionally checks for
#' potentially dangerous function calls.  This is intended as a fast pre-check
#' so that obviously broken code never reaches the child process.
#'
#' @param code Character string of R code to validate.
#' @return A list with components:
#'   \describe{
#'     \item{valid}{Logical. `TRUE` if the code parses without error.}
#'     \item{error}{`NULL` on success, or a character string describing the
#'       parse error.}
#'     \item{warnings}{Character vector of warnings about potentially dangerous
#'       patterns (e.g. `system()`, `.Internal()`).  Empty if none detected.
#'       These are advisory only --- the sandbox handles actual restriction.}
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

  # Check for dangerous patterns (advisory only)
  dangerous <- c("system", "system2", "shell", ".Internal", "Sys.setenv")
  warnings <- character(0)
  for (pattern in dangerous) {
    # Use fixed matching for function-call-like patterns
    escaped <- gsub("\\.", "\\\\.", pattern)
    regex <- paste0("\\b", escaped, "\\s*\\(")
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
