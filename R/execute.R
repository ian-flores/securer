#' Execute R code securely with tool support
#'
#' A convenience wrapper that creates a [SecureSession], executes code, and
#' returns the result. The session is automatically closed when done.
#'
#' @param code Character string of R code to execute.
#' @param tools List of tools created with [securer_tool()], or a named list
#'   of functions (legacy format).
#' @param timeout Timeout in seconds for the execution (default 30).
#' @param sandbox Logical, whether to enable OS-level sandboxing (default TRUE).
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
#' }
#'
#' @export
execute_r <- function(code, tools = list(), timeout = 30, sandbox = TRUE) {
  session <- SecureSession$new(tools = tools, sandbox = sandbox)
  on.exit(session$close())
  session$execute(code, timeout = timeout)
}
