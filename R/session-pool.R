#' @title SecureSessionPool
#' @description R6 class for a pool of pre-warmed [SecureSession] instances.
#'
#' Creates multiple sessions at initialization time so that `$execute()` calls
#' can run immediately on an idle session without waiting for process startup.
#' Sessions are returned to the pool after each execution completes (or errors).
#'
#' @examples
#' \donttest{
#' pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
#' pool$execute("1 + 1")
#' pool$execute("2 + 2")
#' pool$close()
#' }
#'
#' @return An R6 object of class \code{SecureSessionPool}.
#'
#' @export
SecureSessionPool <- R6::R6Class("SecureSessionPool",
  public = list(
    #' @description Create a new SecureSessionPool
    #' @param size Integer, number of sessions to pre-warm (default 4, minimum 1).
    #' @param tools A list of [securer_tool()] objects passed to each session.
    #' @param sandbox Logical, whether to enable OS-level sandboxing.
    #' @param limits Optional named list of resource limits.
    #' @param verbose Logical, whether to emit diagnostic messages.
    initialize = function(size = 4L, tools = list(), sandbox = TRUE,
                          limits = NULL, verbose = FALSE) {
      size <- as.integer(size)
      if (size < 1L) {
        stop("Pool size must be at least 1", call. = FALSE)
      }

      private$pool_tools <- tools
      private$pool_sandbox <- sandbox
      private$pool_limits <- limits
      private$pool_verbose <- verbose
      private$closed <- FALSE

      # Pre-warm all sessions
      private$sessions <- vector("list", size)
      private$busy <- rep(FALSE, size)

      for (i in seq_len(size)) {
        private$sessions[[i]] <- SecureSession$new(
          tools = tools, sandbox = sandbox,
          limits = limits, verbose = verbose
        )
      }
    },

    #' @description Execute R code on an available pooled session
    #' @param code Character string of R code to execute.
    #' @param timeout Timeout in seconds, or `NULL` for no timeout.
    #' @return The result of evaluating the code.
    execute = function(code, timeout = NULL) {
      if (private$closed) {
        stop("Pool is closed", call. = FALSE)
      }

      idx <- private$acquire()
      if (is.null(idx)) {
        stop("All sessions are busy", call. = FALSE)
      }

      # Ensure session is returned to pool even on error
      on.exit(private$release(idx), add = TRUE)

      private$sessions[[idx]]$execute(code, timeout = timeout)
    },

    #' @description Number of sessions in the pool
    #' @return Integer
    size = function() {
      length(private$sessions)
    },

    #' @description Number of idle (non-busy) sessions

    #' @return Integer
    available = function() {
      if (private$closed) return(0L)
      sum(!private$busy)
    },

    #' @description Close all sessions and shut down the pool
    #' @return Invisible self
    close = function() {
      for (i in seq_along(private$sessions)) {
        tryCatch(
          private$sessions[[i]]$close(),
          error = function(e) NULL
        )
      }
      private$sessions <- list()
      private$busy <- logical(0)
      private$closed <- TRUE
      invisible(self)
    }
  ),

  private = list(
    sessions = list(),
    busy = logical(0),
    closed = FALSE,
    pool_tools = list(),
    pool_sandbox = FALSE,
    pool_limits = NULL,
    pool_verbose = FALSE,

    # Find and claim an idle session. Returns index or NULL.
    acquire = function() {
      idle <- which(!private$busy)
      if (length(idle) == 0L) return(NULL)

      # Pick first idle session; check it's alive, restart if needed
      idx <- idle[[1L]]
      if (!private$sessions[[idx]]$is_alive()) {
        private$sessions[[idx]] <- SecureSession$new(
          tools = private$pool_tools,
          sandbox = private$pool_sandbox,
          limits = private$pool_limits,
          verbose = private$pool_verbose
        )
      }
      private$busy[[idx]] <- TRUE
      idx
    },

    # Return a session to the pool
    release = function(idx) {
      private$busy[[idx]] <- FALSE
    }
  )
)
