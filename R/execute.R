#' Execute R code securely with tool support
#'
#' Starts a [SecureSession], runs `code` in it, and returns the result. The
#' session is closed afterwards, even if the code fails.
#'
#' @param code Character string of R code to execute.
#' @param tools List of tools created with [securer_tool()], or a named list
#'   of functions (legacy format).
#' @param timeout Timeout in seconds for the execution, or `NULL` for no
#'   timeout (default 30).
#' @param sandbox Logical, whether to enable OS-level sandboxing (default TRUE).
#' @param limits Optional named list of resource limits (see
#'   [SecureSession] for details).
#' @param verbose Logical, whether to print what the session is doing with
#'   `message()`. Handy for debugging. Wrap the call in `suppressMessages()`
#'   to hide them.
#' @param validate Logical, whether to check the code for syntax errors
#'   before sending it to the child process (default `TRUE`).
#' @param sandbox_strict Logical, whether to stop with an error if the
#'   sandbox tools aren't available (default `FALSE`). See [SecureSession].
#' @param audit_log Optional path to a JSONL file to log session events to.
#'   The default, `NULL`, writes no log.
#'
#' @return The value of the last expression in `code`.
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

  if (.trace_active()) {
    .with_span("securer::execute_r", {
      result <- session$execute(code, timeout = timeout, validate = validate)
      .span_event("execute.complete", list(
        code_length = nchar(code),
        sandbox = sandbox
      ))
      result
    })
  } else {
    session$execute(code, timeout = timeout, validate = validate)
  }
}


#' Run a function with a SecureSession that closes itself
#'
#' Starts a [SecureSession], passes it to `fn`, and closes it when `fn`
#' returns or fails. Use it when you want several calls to share one session,
#' for example to build up variables across calls, without having to
#' remember to close it.
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

  if (.trace_active()) {
    .with_span("securer::with_secure_session", {
      result <- fn(session)
      .span_event("session.complete", list(
        sandbox = sandbox
      ))
      result
    })
  } else {
    fn(session)
  }
}
