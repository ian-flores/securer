#' @title securer: Secure R Code Execution with Tool-Call IPC
#'
#' @description
#' Wraps `callr::r_session` with a bidirectional IPC protocol for
#' pause/resume tool calls, enabling safe execution of LLM-generated R code
#' inside an OS-level sandbox.
#'
#' The main entry points are:
#' * [execute_r()] -- convenience function for one-shot execution
#' * [SecureSession] -- R6 class for persistent sessions with tool support
#' * [securer_tool()] -- define tools that child code can call
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import S7
#' @importFrom R6 R6Class
#' @importFrom jsonlite toJSON fromJSON
#' @importFrom callr r_session r_session_options
#' @importFrom processx conn_create_unix_socket conn_accept_unix_socket
#'   conn_connect_unix_socket conn_write conn_read_lines poll
## usethis namespace: end
NULL
