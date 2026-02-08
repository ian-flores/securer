#' @title SecureSession
#' @description R6 class for secure code execution with tool-call IPC.
#'
#' Wraps a `callr::r_session` with a bidirectional Unix domain socket protocol
#' that allows code running in the child process to pause, call tools on the
#' parent side, and resume with the result.
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' session <- SecureSession$new()
#' session$execute("1 + 1")
#' session$close()
#'
#' # With tools
#' tools <- list(
#'   securer_tool("add", "Add numbers",
#'     fn = function(a, b) a + b,
#'     args = list(a = "numeric", b = "numeric"))
#' )
#' session <- SecureSession$new(tools = tools)
#' session$execute("add(2, 3)")
#' session$close()
#'
#' # With macOS sandbox
#' session <- SecureSession$new(sandbox = TRUE)
#' session$execute("1 + 1")
#' session$close()
#' }
#'
#' @export
SecureSession <- R6::R6Class("SecureSession",
  public = list(
    #' @description Create a new SecureSession
    #' @param tools A list of [securer_tool()] objects, or a named list of
    #'   functions (legacy format for backward compatibility)
    #' @param sandbox Logical, whether to enable the OS-level sandbox.
    #'   On macOS this uses `sandbox-exec` with a Seatbelt profile that
    #'   denies network access and restricts file writes to temp
    #'   directories.  On other platforms a warning is issued and the
    #'   session runs without sandboxing.
    #' @param limits An optional named list of resource limits to apply to the
    #'   child process via `ulimit`.  Supported names: `cpu` (seconds),
    #'   `memory` (bytes, virtual address space), `fsize` (bytes, max file
    #'   size), `nproc` (max processes), `nofile` (max open files),
    #'   `stack` (bytes, stack size).  `NULL` (the default) means no limits.
    #' @param verbose Logical, whether to emit diagnostic messages via
    #'   `message()`.  Useful for debugging.  Users can suppress with
    #'   `suppressMessages()`.
    #' @param audit_log Optional path to a JSONL file for persistent audit
    #'   logging.  If `NULL` (the default), no file logging is performed.
    #'   When a path is provided, structured JSON entries are appended for
    #'   session lifecycle events, executions, and tool calls.
    initialize = function(tools = list(), sandbox = FALSE, limits = NULL,
                          verbose = FALSE, audit_log = NULL) {
      private$raw_tools <- tools
      private$tool_fns <- validate_tools(tools)
      private$sandbox_enabled <- sandbox
      private$limits <- limits
      private$verbose <- verbose
      private$session_id <- basename(tempfile("sess_"))
      if (!is.null(audit_log)) {
        private$audit <- new_audit_logger(audit_log, private$session_id)
      }
      private$start_session()
    },

    #' @description Execute R code in the secure session
    #' @param code Character string of R code to execute
    #' @param timeout Timeout in seconds, or `NULL` for no timeout (default `NULL`)
    #' @param validate Logical, whether to pre-validate the code for syntax
    #'   errors before sending it to the child process (default `TRUE`).
    #' @param output_handler An optional callback function that receives output
    #'   lines (character) as they arrive from the child process. If `NULL`
    #'   (default), output is only collected and returned as the `"output"`
    #'   attribute on the result.
    #' @return The result of evaluating the code, with an `"output"` attribute
    #'   containing all captured stdout/stderr as a character vector.
    execute = function(code, timeout = NULL, validate = TRUE,
                       output_handler = NULL) {
      if (is.null(private$session) || !private$session$is_alive()) {
        stop("Session is not running", call. = FALSE)
      }
      if (private$executing) {
        stop(
          "SecureSession does not support concurrent execute() calls; ",
          "wait for the current execution to complete",
          call. = FALSE
        )
      }
      if (isTRUE(validate)) {
        check <- validate_code(code)
        if (!check$valid) {
          stop(
            "Code has a syntax error and was not executed:\n", check$error,
            call. = FALSE
          )
        }
      }
      private$executing <- TRUE
      on.exit(private$executing <- FALSE)
      private$run_with_tools(code, timeout, output_handler)
    },

    #' @description Close the session and clean up resources
    #' @return Invisible self
    close = function() {
      private$audit_log("session_close")
      private$log("Session closed")
      if (!is.null(private$session)) {
        try(private$session$close(), silent = TRUE)
        private$session <- NULL
      }
      if (!is.null(private$ipc_conn)) {
        try(close(private$ipc_conn), silent = TRUE)
        private$ipc_conn <- NULL
      }
      if (!is.null(private$socket_path) && file.exists(private$socket_path)) {
        unlink(private$socket_path)
      }
      # Clean up sandbox temp files (wrapper script + seatbelt profile + tmp dir)
      if (!is.null(private$sandbox_config)) {
        if (!is.null(private$sandbox_config$wrapper)) {
          unlink(private$sandbox_config$wrapper)
        }
        if (!is.null(private$sandbox_config$profile_path)) {
          unlink(private$sandbox_config$profile_path)
        }
        if (!is.null(private$sandbox_config$sandbox_tmp)) {
          unlink(private$sandbox_config$sandbox_tmp, recursive = TRUE)
        }
        private$sandbox_config <- NULL
      }
      invisible(self)
    },

    #' @description Check if session is alive
    #' @return Logical
    is_alive = function() {
      !is.null(private$session) && private$session$is_alive()
    }
  ),

  private = list(
    session = NULL,
    ipc_conn = NULL,
    socket_path = NULL,
    raw_tools = list(),
    tool_fns = list(),
    executing = FALSE,
    sandbox_enabled = FALSE,
    sandbox_config = NULL,
    limits = NULL,
    verbose = FALSE,
    session_id = NULL,
    audit = NULL,

    audit_log = function(event, ...) {
      if (!is.null(private$audit)) private$audit$log(event, ...)
    },

    log = function(msg) {
      if (private$verbose) message("[securer] ", msg)
    },

    start_session = function() {
      # Create socket path in /tmp to keep the path short.
      # Unix domain sockets are limited to ~104 chars on macOS.  The
      # default tempdir() can be deeply nested (especially during
      # R CMD check), so we use /tmp directly.
      private$socket_path <- tempfile("securer_", tmpdir = "/tmp",
                                      fileext = ".sock")

      # Create server socket
      private$ipc_conn <- processx::conn_create_unix_socket(
        private$socket_path
      )

      # Build session options; optionally wrap with OS sandbox.
      # Pipe stdout/stderr so output can be read incrementally during
      # the event loop (enables streaming output capture).
      session_opts <- callr::r_session_options(
        env = c(SECURER_SOCKET = private$socket_path),
        stdout = "|",
        stderr = "|"
      )

      if (private$sandbox_enabled) {
        private$sandbox_config <- build_sandbox_config(
          private$socket_path, R.home(), limits = private$limits
        )
        if (!is.null(private$sandbox_config$wrapper)) {
          # Override the R binary with our sandbox wrapper script.
          # callr interprets `arch` values containing "/" as a direct
          # path to the R executable (see callr:::setup_r_binary_and_args).
          session_opts$arch <- private$sandbox_config$wrapper
        }
        if (!is.null(private$sandbox_config$env)) {
          # Merge sandbox environment variables (used on Windows where
          # the arch/wrapper trick is not available).
          session_opts$env <- c(session_opts$env, private$sandbox_config$env)
        }
      } else if (!is.null(private$limits)) {
        # No sandbox, but resource limits requested: create a minimal
        # wrapper script that applies ulimit commands before exec'ing R.
        private$sandbox_config <- build_limits_only_wrapper(
          private$limits
        )
        if (!is.null(private$sandbox_config$wrapper)) {
          session_opts$arch <- private$sandbox_config$wrapper
        }
      }

      # Start callr session
      private$session <- callr::r_session$new(
        options = session_opts,
        wait = TRUE
      )

      # Inject runtime into child
      runtime_code <- child_runtime_code()
      private$session$call(function(code) {
        eval(parse(text = code), envir = globalenv())
      }, args = list(code = runtime_code))

      # Wait for the child to connect to our socket.
      # The child's runtime code calls conn_connect_unix_socket() during eval.
      # We need to accept before reading the call result, because the child
      # blocks on connect until we accept.
      #
      # NOTE: processx::conn_accept_unix_socket() transitions the server
      # connection itself to "connected_server" state. It does NOT return a
      # new connection object. After accept, private$ipc_conn is the
      # bidirectional data connection.
      processx::poll(list(private$ipc_conn), 5000)
      processx::conn_accept_unix_socket(private$ipc_conn)

      # Now wait for the call to finish and read the result
      private$session$poll_process(3000)
      private$session$read()

      # If tools were provided as securer_tool objects, inject wrapper
      # functions into the child's global env so user code can call them
      # by name instead of using .securer_call_tool() directly.
      if (length(private$raw_tools) > 0 &&
          inherits(private$raw_tools[[1]], "securer_tool")) {
        wrapper_code <- generate_tool_wrappers(private$raw_tools)
        if (nzchar(wrapper_code)) {
          private$session$call(function(code) {
            eval(parse(text = code), envir = globalenv())
          }, args = list(code = wrapper_code))
          private$session$poll_process(3000)
          private$session$read()
        }
      }

      private$log(sprintf(
        "Session started (sandbox=%s, pid=%s)",
        tolower(as.character(private$sandbox_enabled)),
        private$session$get_pid()
      ))
      private$audit_log("session_start",
        sandbox = private$sandbox_enabled,
        pid = private$session$get_pid()
      )
    },

    run_with_tools = function(code, timeout, output_handler = NULL) {
      exec_start <- Sys.time()
      private$audit_log("execute_start", code = code)
      output_lines <- character()

      # Helper: drain any available stdout/stderr from the child process
      drain_output <- function() {
        repeat {
          out <- private$session$read_output_lines(n = 100)
          err <- private$session$read_error_lines(n = 100)
          lines <- c(out, err)
          if (length(lines) == 0) break
          output_lines <<- c(output_lines, lines)
          if (is.function(output_handler)) {
            for (ln in lines) output_handler(ln)
          }
        }
      }

      # Send code to child for execution via non-blocking call
      private$session$call(function(code) {
        eval(parse(text = code), envir = globalenv())
      }, args = list(code = code))

      # Event loop: poll UDS for tool calls and check process completion
      deadline <- if (!is.null(timeout)) Sys.time() + timeout else NULL

      while (TRUE) {
        poll_ms <- 200L

        if (!is.null(deadline)) {
          remaining_ms <- as.numeric(
            difftime(deadline, Sys.time(), units = "secs")
          ) * 1000
          if (remaining_ms <= 0) {
            private$handle_timeout(timeout)
          }
          poll_ms <- as.integer(min(remaining_ms, 200))
        }

        # Drain stdout/stderr from the child process
        drain_output()

        # Poll the UDS for tool calls from the child
        poll_result <- processx::poll(
          list(private$ipc_conn),
          poll_ms
        )

        # Check if there's data on the UDS (tool call)
        if (poll_result[[1]] == "ready") {
          line <- processx::conn_read_lines(private$ipc_conn, n = 1)
          if (length(line) > 0 && nzchar(line)) {
            request <- jsonlite::fromJSON(line, simplifyVector = FALSE)

            if (identical(request$type, "tool_call")) {
              # Execute the tool on the parent side
              tool_name <- request$tool
              tool_args <- request$args

              # Log the tool call with arguments
              if (private$verbose) {
                args_str <- paste(
                  names(tool_args),
                  tool_args,
                  sep = "=", collapse = ", "
                )
                private$log(sprintf("Tool call: %s(%s)", tool_name, args_str))
              }

              private$audit_log("tool_call",
                tool = tool_name, args = tool_args)

              tool_start <- Sys.time()
              response <- tryCatch({
                if (is.null(private$tool_fns[[tool_name]])) {
                  list(error = paste0("Unknown tool: ", tool_name))
                } else {
                  result <- do.call(private$tool_fns[[tool_name]], tool_args)
                  list(value = result)
                }
              }, error = function(e) {
                list(error = conditionMessage(e))
              })

              # Log the tool result
              if (private$verbose) {
                elapsed <- sprintf(
                  "%.2fs",
                  as.numeric(difftime(Sys.time(), tool_start, units = "secs"))
                )
                if (!is.null(response$error)) {
                  private$log(sprintf(
                    "Tool result: %s -> error: %s (%s)",
                    tool_name, response$error, elapsed
                  ))
                } else {
                  result_str <- tryCatch(
                    paste(utils::head(response$value, 1), collapse = ", "),
                    error = function(e) "<complex>"
                  )
                  private$log(sprintf(
                    "Tool result: %s -> %s (%s)",
                    tool_name, result_str, elapsed
                  ))
                }
              }

              private$audit_log("tool_result",
                tool = tool_name,
                error = response$error,
                elapsed_secs = as.numeric(
                  difftime(Sys.time(), tool_start, units = "secs")
                )
              )

              # Send response back to child
              response_json <- jsonlite::toJSON(response, auto_unbox = TRUE)
              processx::conn_write(
                private$ipc_conn,
                paste0(response_json, "\n")
              )
            }
          }
        }

        # Check if the session has finished (poll the process)
        proc_poll <- private$session$poll_process(0)
        if (proc_poll == "ready") {
          # Final drain to capture any remaining complete lines
          drain_output()
          result <- private$session$read()
          # Also capture any partial lines that didn't end with newline
          trailing_out <- private$session$read_output()
          trailing_err <- private$session$read_error()
          for (raw in c(trailing_out, trailing_err)) {
            if (nzchar(raw)) {
              parts <- strsplit(raw, "\n", fixed = TRUE)[[1]]
              output_lines <- c(output_lines, parts)
              if (is.function(output_handler)) {
                for (ln in parts) output_handler(ln)
              }
            }
          }
          elapsed <- sprintf(
            "%.2fs",
            as.numeric(difftime(Sys.time(), exec_start, units = "secs"))
          )
          if (!is.null(result$error)) {
            private$log(sprintf(
              "Execution error: %s (%s)",
              conditionMessage(result$error), elapsed
            ))
            private$audit_log("execute_error",
              error = conditionMessage(result$error),
              elapsed = elapsed
            )
            stop(result$error)
          }
          private$log(sprintf("Execution complete (%s)", elapsed))
          private$audit_log("execute_complete", elapsed = elapsed)
          val <- result$result
          if (length(output_lines) > 0) {
            attr(val, "output") <- output_lines
          }
          return(val)
        }
      }
    },

    handle_timeout = function(timeout) {
      private$log(sprintf("Execution timed out after %ss", timeout))
      private$audit_log("execute_timeout", timeout_secs = timeout)
      # Kill the child process and restart so the session remains usable
      try(private$session$close(), silent = TRUE)
      private$session <- NULL
      if (!is.null(private$ipc_conn)) {
        try(close(private$ipc_conn), silent = TRUE)
        private$ipc_conn <- NULL
      }
      if (!is.null(private$socket_path) && file.exists(private$socket_path)) {
        unlink(private$socket_path)
      }

      # Restart the session so it's usable for future execute() calls
      private$start_session()

      label <- if (timeout == 1) "1 second" else paste(timeout, "seconds")
      stop(
        paste("Execution timed out after", label),
        call. = FALSE
      )
    }
  )
)
