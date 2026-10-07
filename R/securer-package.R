#' @title securer: run LLM-written R code in a sandbox
#'
#' @description
#' securer runs R code in a child R process inside an OS sandbox. The code
#' can call tools, which are functions that run in your own session: the
#' child pauses, your session runs the tool, and the child carries on with
#' the result.
#'
#' Start with:
#' * [execute_r()] to run one piece of code and shut the session down.
#' * [SecureSession] to keep a session open across many calls.
#' * [securer_tool()] to define the tools the code can call.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import S7
#' @importFrom cli cli_abort cli_text cli_ul
#' @importFrom lifecycle deprecate_warn deprecated
#' @importFrom R6 R6Class
#' @importFrom jsonlite toJSON fromJSON
#' @importFrom callr r_session r_session_options
#' @importFrom processx conn_create_unix_socket conn_accept_unix_socket
#'   conn_connect_unix_socket conn_write conn_read_lines poll
## usethis namespace: end
NULL

# OpenTelemetry tracer name for this package, discovered/used by the otel
# soft dependency (see R/utils-trace.R).  Deliberately not exported.
otel_tracer_name <- "com.github.ian-flores.securer"
