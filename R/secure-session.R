# Module-level list that holds closed callr/processx objects to prevent
# heap corruption.  Explicitly closing processx connections (via close() or
# callr::r_session$close()) then letting GC finalize the same objects
# causes a C-level double-free in processx 3.8.6 that corrupts the malloc
# heap ("BUG IN CLIENT OF LIBMALLOC: memory corruption of free block").
#
# Workaround: instead of closing connections, we kill the child process
# and park the R6 objects here.  The GC finalizer handles cleanup safely
# since each connection is only closed once.  References accumulate for
# the life of the R session — the memory cost is negligible (~1 KB per
# session) since the child processes are already dead.
.securer_closed_sessions <- new.env(parent = emptyenv())
.securer_closed_sessions$refs <- list()
.securer_closed_sessions_add <- function(obj) {
  .securer_closed_sessions$refs <- c(.securer_closed_sessions$refs, list(obj))
}

#' @title SecureSession
#' @description R6 class for secure code execution with tool-call IPC.
#'
#' Wraps a `callr::r_session` with a bidirectional Unix domain socket protocol
#' that allows code running in the child process to pause, call tools on the
#' parent side, and resume with the result.
#'
#' @examples
#' \donttest{
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
#' }
#' \donttest{
#' # With sandbox (requires platform-specific tools)
#' session <- SecureSession$new(sandbox = TRUE)
#' session$execute("1 + 1")
#' session$close()
#' }
#'
#' @return An R6 object of class \code{SecureSession}.
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
    #'   namespace isolation.  On Windows this provides environment
    #'   isolation (clean HOME/TMPDIR, empty R_LIBS_USER) and resource
    #'   limits (memory, CPU time, process count) via Job Objects.
    #'   On other platforms the session runs without sandboxing.
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
    #' @param sandbox_strict Logical, whether to error if sandbox tools are
    #'   not available on the current platform (default `FALSE`).  When
    #'   `TRUE` and `sandbox = TRUE`, the session will stop with an
    #'   informative error if the OS-level sandbox cannot be set up.
    #'   When `FALSE` (default), the existing behavior is preserved:
    #'   a warning is emitted and the session continues without sandboxing.
    #' @param audit_log Optional path to a JSONL file for persistent audit
    #'   logging.  If `NULL` (the default), no file logging is performed.
    #'   When a path is provided, structured JSON entries are appended for
    #'   session lifecycle events, executions, and tool calls.
    initialize = function(tools = list(), sandbox = FALSE, limits = NULL,
                          verbose = FALSE, sandbox_strict = FALSE,
                          audit_log = NULL) {
      private$raw_tools <- tools
      validated <- validate_tools(tools)
      private$tool_fns <- validated$fns
      private$tool_arg_meta <- validated$arg_meta
      private$sandbox_enabled <- sandbox
      private$sandbox_strict <- sandbox_strict
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
      if (!is.null(output_handler) && !is.function(output_handler)) {
        stop("`output_handler` must be a function or NULL", call. = FALSE)
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
        # Kill the child process but do NOT call $close() on the callr
        # session.  callr$close() calls processx_conn_close() on internal
        # pipe connections; when GC later finalizes those same connection
        # objects, the C-level double-close corrupts the malloc heap
        # (processx 3.8.6, "BUG IN CLIENT OF LIBMALLOC").
        # Instead, just kill the process and park the R6 object.  The GC
        # finalizer will clean up connections and temp files safely.
        try(private$session$kill(), silent = TRUE)
        .securer_closed_sessions_add(private$session)
        private$session <- NULL
      }
      private$child_pid <- NULL
      # Disarm the GC finalizer so it won't try to kill a recycled PID
      if (!is.null(private$gc_prevent)) {
        private$gc_prevent$pid <- NULL
        private$gc_prevent <- NULL
      }
      if (!is.null(private$ipc_conn)) {
        # Don't call close() on the processx connection — the C-level
        # finalizer will close the file descriptor during GC.  Explicitly
        # closing + later GC finalization causes a double-free that
        # corrupts the malloc heap (processx 3.8.6).
        .securer_closed_sessions_add(private$ipc_conn)
        private$ipc_conn <- NULL
      }
      # Filesystem cleanup: save paths as local variables first, then
      # NULL out the private fields.  This avoids segfaults when close()
      # is called during GC finalization (private fields may already be
      # freed, but local copies on the stack are safe).
      sock_path <- private$socket_path
      sock_dir  <- private$socket_dir
      sb_config <- private$sandbox_config
      private$socket_path    <- NULL
      private$socket_dir     <- NULL
      private$sandbox_config <- NULL
      if (is.character(sock_path) && length(sock_path) == 1 &&
          file.exists(sock_path)) {
        unlink(sock_path)
      }
      if (is.character(sock_dir) && length(sock_dir) == 1 &&
          dir.exists(sock_dir)) {
        unlink(sock_dir, recursive = TRUE)
      }
      if (is.list(sb_config)) {
        if (is.character(sb_config$wrapper))
          unlink(sb_config$wrapper)
        if (is.character(sb_config$profile_path))
          unlink(sb_config$profile_path)
        if (is.character(sb_config$sandbox_tmp))
          unlink(sb_config$sandbox_tmp, recursive = TRUE)
      }
      invisible(self)
    },

    #' @description Check if session is alive
    #' @return Logical
    is_alive = function() {
      !is.null(private$session) && private$session$is_alive()
    },

    #' @description Format method for display
    #' @param ... Ignored.
    #' @return A character string describing the session.
    format = function(...) {
      status <- if (self$is_alive()) "running" else "stopped"
      sandbox_str <- if (private$sandbox_enabled) "enabled" else "disabled"
      n_tools <- length(private$tool_fns)
      pid_str <- if (!is.null(private$child_pid)) {
        as.character(private$child_pid)
      } else {
        "NA"
      }
      sprintf("<SecureSession> [%s] pid=%s sandbox=%s tools=%d",
              status, pid_str, sandbox_str, n_tools)
    },

    #' @description Print method
    #' @param ... Ignored.
    #' @return Invisible self.
    print = function(...) {
      cat(self$format(), "\n")
      invisible(self)
    },

    #' @description List registered tools and their argument specs
    #' @return A named list of tool information. Each element contains
    #'   `name` and `args` fields. Returns an empty list if no tools are
    #'   registered.
    tools = function() {
      if (length(private$raw_tools) == 0) return(list())
      # If tools are securer_tool objects, return structured info
      if (inherits(private$raw_tools[[1]], "securer_tool")) {
        result <- lapply(private$raw_tools, function(tool) {
          list(name = tool$name, args = tool$args)
        })
        names(result) <- vapply(private$raw_tools, function(t) t$name,
                                character(1))
        return(result)
      }
      # Legacy format: named list of bare functions
      lapply(names(private$raw_tools), function(nm) {
        list(name = nm, args = NULL)
      })
    },

    #' @description Restart the child R process
    #'
    #' Kills the current child process, cleans up the socket, and starts
    #' a fresh child with the runtime and tool wrappers re-injected.
    #' The session remains usable for subsequent `$execute()` calls.
    #' @return Invisible self.
    restart = function() {
      if (private$executing) {
        stop(
          "Cannot restart while an execution is in progress",
          call. = FALSE
        )
      }
      private$log("Restarting session")
      private$audit_log("session_restart")

      # Kill the child process
      if (!is.null(private$session)) {
        try(private$session$kill(), silent = TRUE)
        .securer_closed_sessions_add(private$session)
        private$session <- NULL
      }

      # Clean up the old socket
      if (!is.null(private$ipc_conn)) {
        .securer_closed_sessions_add(private$ipc_conn)
        private$ipc_conn <- NULL
      }
      if (!is.null(private$socket_path) && file.exists(private$socket_path)) {
        unlink(private$socket_path)
      }
      if (!is.null(private$socket_dir) && dir.exists(private$socket_dir)) {
        unlink(private$socket_dir, recursive = TRUE)
        private$socket_dir <- NULL
      }

      # Clean up old sandbox temp files
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

      # Start a fresh session (re-injects runtime + tool wrappers)
      private$start_session()
      invisible(self)
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
    sandbox_strict = FALSE,
    sandbox_config = NULL,
    limits = NULL,
    verbose = FALSE,
    session_id = NULL,
    child_pid = NULL,
    gc_prevent = NULL,
    audit = NULL,

    # Build a sanitized environment for the child process.
    # Uses an allowlist: only safe vars are inherited; all others are set
    # to NA (which callr interprets as "remove from child").
    build_child_env = function() {
      # Security note: R_LIBS and R_LIBS_USER are intentionally excluded
      # from the allowlist. These variables can point to attacker-controlled
      # directories, allowing malicious packages with .onLoad hooks to
      # execute arbitrary code in the child process, bypassing sandbox
      # restrictions. The child inherits only R_HOME and R_LIBS_SITE
      # (system-level library paths controlled by the R installation).
      # R_LIBS_USER is explicitly set to "" to prevent user-level library
      # injection on all platforms.
      safe_vars <- c(
        "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE",
        "LC_MESSAGES", "LC_COLLATE", "LC_MONETARY", "LC_NUMERIC", "LC_TIME",
        "SHELL", "TMPDIR", "TZ", "TERM",
        "R_HOME", "R_LIBS_SITE",
        "R_PLATFORM", "R_ARCH"
      )
      parent_env <- Sys.getenv()
      unsafe_names <- setdiff(names(parent_env), safe_vars)
      clear_env <- setNames(rep(NA_character_, length(unsafe_names)), unsafe_names)
      c(clear_env,
        R_LIBS_USER = "",
        SECURER_SOCKET = private$socket_path,
        SECURER_TOKEN = private$ipc_token)
    },

    # NOTE: No private$finalize() here.  R6 finalization can segfault
    # when private fields (strings, external pointers) are freed before
    # the finalizer runs.  Instead, start_session() registers a plain
    # reg.finalizer() on a dedicated environment that holds only the
    # child PID (a safe integer).  See start_session() below.

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
      # deeply nested during R CMD check).  On Windows, /tmp does not
      # exist so we use TEMP/TMP or fall back to tempdir().
      tmpdir_base <- if (.Platform$OS.type == "windows") {
        Sys.getenv("TEMP", Sys.getenv("TMP", tempdir()))
      } else {
        "/tmp"
      }
      private$socket_dir <- tempfile("securer_", tmpdir = tmpdir_base)
      dir.create(private$socket_dir, mode = "0700")
      Sys.chmod(private$socket_dir, "0700")
      private$socket_path <- file.path(private$socket_dir, "ipc.sock")

      # Generate a random authentication token.  The child must send
      # this as its first message after connecting; the parent rejects
      # connections that don't present the correct token.
      private$ipc_token <- if (file.exists("/dev/urandom")) {
        con <- suppressWarnings(file("/dev/urandom", open = "rb"))
        raw_bytes <- readBin(con, "raw", 32)
        close(con)
        paste0(sprintf("%02x", as.integer(raw_bytes)), collapse = "")
      } else {
        paste0(sample(c(letters, LETTERS, 0:9), 32, replace = TRUE),
               collapse = "")
      }

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
        # Strict mode: error if sandbox was requested but tools are unavailable
        if (private$sandbox_strict &&
            is.null(private$sandbox_config$wrapper) &&
            is.null(private$sandbox_config$env)) {
          stop(
            "sandbox_strict is TRUE but OS-level sandbox tools are not ",
            "available on this platform. Install the required tools ",
            "(sandbox-exec on macOS, bwrap on Linux) or set ",
            "sandbox_strict = FALSE to allow fallback.",
            call. = FALSE
          )
        }
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
      # Store the child PID as a plain integer for the GC finalizer
      # (R6 objects and external pointers are unsafe to access during GC).
      private$child_pid <- private$session$get_pid()

      # Apply post-start limits (Windows Job Objects)
      if (!is.null(private$sandbox_config$apply_limits)) {
        private$sandbox_config$apply_limits(private$child_pid)
      }

      # Register a standalone GC finalizer using a plain environment
      # that holds only the child PID (an integer, safe during GC).
      # This avoids segfaults from accessing R6 private fields that may
      # be freed before the finalizer runs.
      pid_env <- new.env(parent = emptyenv())
      pid_env$pid <- private$child_pid
      reg.finalizer(pid_env, function(e) {
        try(tools::pskill(e$pid, tools::SIGKILL), silent = TRUE)
      }, onexit = TRUE)
      private$gc_prevent <- pid_env

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
        .securer_closed_sessions_add(private$ipc_conn)
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
      total_messages <- 0L
      max_messages <- if (!is.null(max_tool_calls)) {
        max_tool_calls * 10L
      } else {
        1000L
      }

      # Helper: drain any available stdout/stderr from the child process
      drain_output <- function() {
        repeat {
          out <- private$session$read_output_lines(n = 100)
          err <- private$session$read_error_lines(n = 100)
          lines <- c(out, err)
          if (length(lines) == 0) break
          output_lines <<- c(output_lines, lines)
          if (is.function(output_handler)) {
            for (ln in lines) {
              tryCatch(output_handler(ln), error = function(e) NULL)
            }
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

            # --- Total message rate limiting (I4 fix) ---
            total_messages <- total_messages + 1L
            if (total_messages > max_messages) {
              stop(
                sprintf(
                  "Maximum IPC messages (%d) exceeded; possible flood attack",
                  max_messages
                ),
                call. = FALSE
              )
            }

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
              if (!is.null(expected_args) &&
                  !is.null(tool_args) && length(tool_args) > 0) {
                # When expected_args is empty (tool defined with args=list()),
                # ALL provided arguments are unexpected (T4 fix).
                # When expected_args is non-empty, only check for extras.
                actual_names <- names(tool_args)
                unexpected <- if (length(expected_args) == 0) {
                  actual_names
                } else {
                  setdiff(actual_names, expected_args)
                }
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
                list(error = sanitize_error_message(conditionMessage(e)))
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

              result_summary <- if (!is.null(response$error)) {
                NULL
              } else {
                tryCatch(
                  substr(deparse(response$value, control = "keepNA")[1], 1, 500),
                  error = function(e) "<unserializable>"
                )
              }
              private$audit_log("tool_result",
                tool = tool_name,
                error = response$error,
                result_summary = result_summary,
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
            } else {
              # --- Unknown message type warning (I4 fix) ---
              warning(
                sprintf(
                  "Unknown IPC message type: %s",
                  sQuote(request$type)
                ),
                call. = FALSE
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
                for (ln in parts) {
                  tryCatch(output_handler(ln), error = function(e) NULL)
                }
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
      try(private$session$kill(), silent = TRUE)
      .securer_closed_sessions_add(private$session)
      private$session <- NULL
      if (!is.null(private$ipc_conn)) {
        .securer_closed_sessions_add(private$ipc_conn)
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
