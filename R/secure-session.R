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
    initialize = function(tools = list(), sandbox = FALSE) {
      private$raw_tools <- tools
      private$tool_fns <- validate_tools(tools)
      private$sandbox_enabled <- sandbox
      private$start_session()
    },

    #' @description Execute R code in the secure session
    #' @param code Character string of R code to execute
    #' @param timeout Timeout in seconds (default 30)
    #' @return The result of evaluating the code
    execute = function(code, timeout = 30) {
      if (is.null(private$session) || !private$session$is_alive()) {
        stop("Session is not running", call. = FALSE)
      }
      private$run_with_tools(code, timeout)
    },

    #' @description Close the session and clean up resources
    #' @return Invisible self
    close = function() {
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
      # Clean up sandbox temp files (wrapper script + seatbelt profile)
      if (!is.null(private$sandbox_config)) {
        if (!is.null(private$sandbox_config$wrapper)) {
          unlink(private$sandbox_config$wrapper)
        }
        if (!is.null(private$sandbox_config$profile_path)) {
          unlink(private$sandbox_config$profile_path)
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
    sandbox_enabled = FALSE,
    sandbox_config = NULL,

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

      # Build session options; optionally wrap with OS sandbox
      session_opts <- callr::r_session_options(
        env = c(SECURER_SOCKET = private$socket_path)
      )

      if (private$sandbox_enabled) {
        private$sandbox_config <- build_sandbox_config(
          private$socket_path, R.home()
        )
        if (!is.null(private$sandbox_config$wrapper)) {
          # Override the R binary with our sandbox wrapper script.
          # callr interprets `arch` values containing "/" as a direct
          # path to the R executable (see callr:::setup_r_binary_and_args).
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
    },

    run_with_tools = function(code, timeout) {
      # Send code to child for execution via non-blocking call
      private$session$call(function(code) {
        eval(parse(text = code), envir = globalenv())
      }, args = list(code = code))

      # Event loop: poll UDS for tool calls and check process completion
      deadline <- Sys.time() + timeout

      while (TRUE) {
        remaining <- as.numeric(
          difftime(deadline, Sys.time(), units = "secs")
        ) * 1000
        if (remaining <= 0) {
          stop("Execution timed out", call. = FALSE)
        }

        # Poll the UDS for tool calls from the child
        poll_result <- processx::poll(
          list(private$ipc_conn),
          as.integer(min(remaining, 200))
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
          result <- private$session$read()
          if (!is.null(result$error)) {
            stop(result$error)
          }
          return(result$result)
        }
      }
    }
  )
)
