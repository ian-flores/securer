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
    #'   directories.  On Linux this uses bubblewrap (`bwrap`) with full
    #'   namespace isolation.  On Windows, `sandbox = TRUE` raises an
    #'   error because OS-level isolation is not available; use
    #'   `sandbox = FALSE` with explicit limits, or run inside a
    #'   container.  On other platforms the session runs without
    #'   sandboxing.
    #' @param limits An optional named list of resource limits to apply to the
    #'   child process via `ulimit`.  Supported names: `cpu` (seconds),
    #'   `memory` (bytes, virtual address space), `fsize` (bytes, max file
    #'   size), `nproc` (max processes), `nofile` (max open files),
    #'   `stack` (bytes, stack size).  When `sandbox = TRUE` and `limits`
    #'   is `NULL` (the default), sensible defaults are applied automatically
    #'   (see [default_limits()]).  Pass `limits = list()` to explicitly
    #'   disable resource limits.  When `sandbox = FALSE`, `NULL` means
    #'   no limits.
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
      validated <- validate_tools(tools)
      private$tool_fns <- validated$fns
      private$tool_arg_meta <- validated$arg_meta
      private$sandbox_enabled <- sandbox
      # Apply default resource limits when sandboxing is enabled and
      # no explicit limits were provided.  Users can pass limits = list()
      # (empty list) to explicitly disable defaults.
      if (sandbox && is.null(limits)) {
        limits <- default_limits()
      }
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
    #' @param max_tool_calls Maximum number of tool calls allowed in this
    #'   execution, or `NULL` for unlimited (default `NULL`).
    #' @return The result of evaluating the code, with an `"output"` attribute
    #'   containing all captured stdout/stderr as a character vector.
    execute = function(code, timeout = NULL, validate = TRUE,
                       output_handler = NULL, max_tool_calls = NULL) {
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
      private$run_with_tools(code, timeout, output_handler, max_tool_calls)
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
      # Clean up the private socket directory
      if (!is.null(private$socket_dir) && dir.exists(private$socket_dir)) {
        unlink(private$socket_dir, recursive = TRUE)
        private$socket_dir <- NULL
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
    socket_dir = NULL,
    ipc_token = NULL,
    raw_tools = list(),
    tool_fns = list(),
    tool_arg_meta = list(),
    executing = FALSE,
    sandbox_enabled = FALSE,
    sandbox_config = NULL,
    limits = NULL,
    verbose = FALSE,
    session_id = NULL,
    audit = NULL,

    # Build a sanitized environment for the child process.
    # Uses an allowlist: only safe vars are inherited; all others are set
    # to NA (which callr interprets as "remove from child").
    build_child_env = function() {
      safe_vars <- c(
        "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE",
        "LC_MESSAGES", "LC_COLLATE", "LC_MONETARY", "LC_NUMERIC", "LC_TIME",
        "SHELL", "TMPDIR", "TZ", "TERM",
        "R_HOME", "R_LIBS", "R_LIBS_SITE", "R_LIBS_USER",
        "R_PLATFORM", "R_ARCH"
      )
      parent_env <- Sys.getenv()
      unsafe_names <- setdiff(names(parent_env), safe_vars)
      clear_env <- setNames(rep(NA_character_, length(unsafe_names)), unsafe_names)
      c(clear_env,
        SECURER_SOCKET = private$socket_path,
        SECURER_TOKEN = private$ipc_token)
    },

    finalize = function() {
      self$close()
    },

    audit_log = function(event, ...) {
      if (!is.null(private$audit)) private$audit$log(event, ...)
    },

    log = function(msg) {
      if (private$verbose) message("[securer] ", msg)
    },

    start_session = function() {
      # Create a private directory for the socket with restrictive
      # permissions (0700) to prevent TOCTOU races and unauthorized
      # connections.  Unix domain sockets are limited to ~104 chars on
      # macOS, so we use /tmp directly (not tempdir() which can be
      # deeply nested during R CMD check).
      private$socket_dir <- tempfile("securer_", tmpdir = "/tmp")
      dir.create(private$socket_dir, mode = "0700")
      private$socket_path <- file.path(private$socket_dir, "ipc.sock")

      # Generate a random authentication token.  The child must send
      # this as its first message after connecting; the parent rejects
      # connections that don't present the correct token.
      private$ipc_token <- paste0(
        sample(c(letters, LETTERS, 0:9), 32, replace = TRUE),
        collapse = ""
      )

      # Create server socket
      private$ipc_conn <- processx::conn_create_unix_socket(
        private$socket_path
      )

      # Build session options; optionally wrap with OS sandbox.
      # Pipe stdout/stderr so output can be read incrementally during
      # the event loop (enables streaming output capture).
      session_opts <- callr::r_session_options(
        env = private$build_child_env(),
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

      # Validate the authentication token sent by the child.
      # The child sends the token as its first message immediately
      # after connecting.  Reject connections with wrong tokens.
      processx::poll(list(private$ipc_conn), 5000)
      auth_line <- processx::conn_read_lines(private$ipc_conn, n = 1)
      if (length(auth_line) == 0 || !identical(auth_line, private$ipc_token)) {
        try(close(private$ipc_conn), silent = TRUE)
        private$ipc_conn <- NULL
        stop("IPC authentication failed: invalid token from child process",
             call. = FALSE)
      }

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

    # Maximum IPC message size in bytes (1 MB default). Messages larger
    # than this are rejected before JSON parsing to prevent resource
    # exhaustion attacks.
    max_ipc_message_size = 1048576L,

    run_with_tools = function(code, timeout, output_handler = NULL,
                              max_tool_calls = NULL) {
      exec_start <- Sys.time()
      private$audit_log("execute_start", code = code)
      output_lines <- character()
      tool_call_count <- 0L

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

            # --- IPC message size check (Finding 10) ---
            if (nchar(line, type = "bytes") > private$max_ipc_message_size) {
              stop(
                "IPC message too large (",
                nchar(line, type = "bytes"), " bytes, max ",
                private$max_ipc_message_size, ")",
                call. = FALSE
              )
            }

            request <- jsonlite::fromJSON(line, simplifyVector = FALSE)

            # --- JSON schema validation (Finding 10) ---
            if (!is.list(request)) {
              stop("Malformed IPC message: expected a JSON object",
                   call. = FALSE)
            }
            if (!is.character(request$type) || length(request$type) != 1) {
              stop("Malformed IPC message: 'type' must be a scalar string",
                   call. = FALSE)
            }

            if (identical(request$type, "tool_call")) {
              # Validate tool_call-specific fields
              if (!is.character(request$tool) || length(request$tool) != 1) {
                stop("Malformed IPC message: 'tool' must be a scalar string",
                     call. = FALSE)
              }
              if (!is.null(request$args) && !is.list(request$args)) {
                stop("Malformed IPC message: 'args' must be a list or null",
                     call. = FALSE)
              }

              # --- Rate limiting (Finding 14) ---
              tool_call_count <- tool_call_count + 1L
              if (!is.null(max_tool_calls) &&
                  tool_call_count > max_tool_calls) {
                stop(
                  sprintf("Maximum tool calls (%d) exceeded",
                          max_tool_calls),
                  call. = FALSE
                )
              }

              # Execute the tool on the parent side
              tool_name <- request$tool
              tool_args <- request$args

              # Validate tool_name is a scalar string and in the allowlist
              if (!is.character(tool_name) || length(tool_name) != 1 ||
                  !nzchar(tool_name) ||
                  !grepl("^[A-Za-z.][A-Za-z0-9_.]*$", tool_name)) {
                tool_name <- "<invalid>"
              }

              # --- Parent-side argument validation (Finding 5) ---
              # Ensure tool_args is a list (not some other type)
              if (!is.null(tool_args) && !is.list(tool_args)) {
                tool_args <- list()
              }

              # If we have arg metadata for this tool, validate arg names
              expected_args <- private$tool_arg_meta[[tool_name]]
              if (!is.null(expected_args) && length(expected_args) > 0 &&
                  !is.null(tool_args) && length(tool_args) > 0) {
                actual_names <- names(tool_args)
                unexpected <- setdiff(actual_names, expected_args)
                if (length(unexpected) > 0) {
                  # Send error back to child rather than crashing
                  response <- list(
                    error = sprintf(
                      "Unexpected arguments for tool '%s': %s",
                      tool_name,
                      paste(sQuote(unexpected), collapse = ", ")
                    )
                  )
                  response_json <- jsonlite::toJSON(
                    response, auto_unbox = TRUE
                  )
                  processx::conn_write(
                    private$ipc_conn,
                    paste0(response_json, "\n")
                  )
                  next
                }
              }

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
      if (!is.null(private$socket_dir) && dir.exists(private$socket_dir)) {
        unlink(private$socket_dir, recursive = TRUE)
        private$socket_dir <- NULL
      }

      # Clean up old sandbox temp files before restarting
      if (!is.null(private$sandbox_config)) {
        if (!is.null(private$sandbox_config$wrapper)) {
          try(unlink(private$sandbox_config$wrapper), silent = TRUE)
        }
        if (!is.null(private$sandbox_config$profile_path)) {
          try(unlink(private$sandbox_config$profile_path), silent = TRUE)
        }
        if (!is.null(private$sandbox_config$sandbox_tmp)) {
          try(unlink(private$sandbox_config$sandbox_tmp, recursive = TRUE),
              silent = TRUE)
        }
        private$sandbox_config <- NULL
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
