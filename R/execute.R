#' Execute R code securely with tool support
#'
#' A convenience wrapper that creates a [SecureSession], executes code, and
#' returns the result. The session is automatically closed when done.
#'
#' @param code Character string of R code to execute.
#' @param tools List of tools created with [securer_tool()], or a named list
#'   of functions (legacy format).
#' @param timeout Timeout in seconds for the execution, or `NULL` for no
#'   timeout (default 30).
#' @param sandbox Logical, whether to enable OS-level sandboxing (default TRUE).
#' @param limits Optional named list of resource limits (see
#'   [SecureSession] for details).
#' @param verbose Logical, whether to emit diagnostic messages via
#'   `message()`.  Useful for debugging.  Users can suppress with
#'   `suppressMessages()`.
#' @param validate Logical, whether to pre-validate the code for syntax
#'   errors before sending it to the child process (default `TRUE`).
#' @param audit_log Optional path to a JSONL file for persistent audit
#'   logging (default `NULL`, no file logging).
#'
#' @return The result of evaluating `code` in the secure session.
#'
#' @examples
#' \dontrun{
#' # Simple computation
#' execute_r("1 + 1")
#'
#' # With tools
#' result <- execute_r(
#'   code = 'add(2, 3)',
#'   tools = list(
#'     securer_tool("add", "Add two numbers",
#'       fn = function(a, b) a + b,
#'       args = list(a = "numeric", b = "numeric"))
#'   )
#' )
#'
#' # With resource limits
#' execute_r("1 + 1", limits = list(cpu = 10, memory = 256 * 1024 * 1024))
#' }
#'
#' @export
execute_r <- function(code, tools = list(), timeout = 30, sandbox = TRUE,
                      limits = NULL, verbose = FALSE, validate = TRUE,
                      audit_log = NULL) {
  session <- SecureSession$new(tools = tools, sandbox = sandbox,
                               limits = limits, verbose = verbose,
                               audit_log = audit_log)
  on.exit(session$close())
  session$execute(code, timeout = timeout, validate = validate)
}
