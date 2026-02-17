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
#' @param sandbox_strict Logical, whether to error if sandbox tools are
#'   not available (default `FALSE`).  See [SecureSession] for details.
#' @param audit_log Optional path to a JSONL file for persistent audit
#'   logging (default `NULL`, no file logging).
#'
#' @return The result of evaluating `code` in the secure session.
#'
#' @examples
#' \donttest{
#' # Simple computation
#' execute_r("1 + 1", sandbox = FALSE)
#'
#' # With tools
#' result <- execute_r(
#'   code = 'add(2, 3)',
#'   tools = list(
#'     securer_tool("add", "Add two numbers",
#'       fn = function(a, b) a + b,
#'       args = list(a = "numeric", b = "numeric"))
#'   ),
#'   sandbox = FALSE
#' )
#' }
#' \dontrun{
#' # With resource limits (Unix only)
#' execute_r("1 + 1", limits = list(cpu = 10, memory = 256 * 1024 * 1024))
#' }
#'
#' @export
execute_r <- function(code, tools = list(), timeout = 30, sandbox = TRUE,
                      limits = NULL, verbose = FALSE, validate = TRUE,
                      sandbox_strict = FALSE, audit_log = NULL) {
  session <- SecureSession$new(tools = tools, sandbox = sandbox,
                               limits = limits, verbose = verbose,
                               sandbox_strict = sandbox_strict,
                               audit_log = audit_log)
  on.exit(session$close())
  session$execute(code, timeout = timeout, validate = validate)
}


#' Execute code with an auto-managed SecureSession
#'
#' Creates a [SecureSession], passes it to a user function, and guarantees
#' cleanup via [on.exit()].
#' This is useful when you need to run multiple executions on the same session
#' (e.g., building up state across calls) without worrying about leaked
#' processes.
#'
#' @param fn A function that receives a [SecureSession] as its first argument.
#' @param tools List of [securer_tool()] objects to register in the session.
#' @param sandbox Logical, whether to enable OS-level sandboxing (default `TRUE`).
#' @param ... Additional arguments passed to [SecureSession]`$new()`.
#' @return The return value of `fn(session)`.
#'
#' @examples
#' \donttest{
#' # Run multiple commands on the same session
#' result <- with_secure_session(function(session) {
#'   session$execute("x <- 10")
#'   session$execute("x * 2")
#' }, sandbox = FALSE)
#'
#' # With tools
#' result <- with_secure_session(
#'   fn = function(session) {
#'     session$execute("add(2, 3)")
#'   },
#'   tools = list(
#'     securer_tool("add", "Add two numbers",
#'       fn = function(a, b) a + b,
#'       args = list(a = "numeric", b = "numeric"))
#'   ),
#'   sandbox = FALSE
#' )
#' }
#'
#' @export
with_secure_session <- function(fn, tools = list(), sandbox = TRUE, ...) {
  session <- SecureSession$new(tools = tools, sandbox = sandbox, ...)
  on.exit(session$close(), add = TRUE)
  fn(session)
}
