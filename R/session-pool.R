#' @title SecureSessionPool
#' @description An R6 class for a pool of [SecureSession] objects that are
#' started ahead of time.
#'
#' The pool starts all its sessions when you create it, so `$execute()` can
#' use an idle one straight away instead of waiting for R to start. Each
#' session goes back to the pool when its run finishes, whether it succeeded
#' or failed.
#'
#' @section Threads and forks:
#' \code{SecureSessionPool} isn't thread-safe. Handing out and taking back
#' sessions uses no locks. If you use pools from several processes (for
#' example with \code{parallel::mclapply} or \code{future}), create a pool
#' in each process. Two processes sharing one pool can end up grabbing the
#' same session.
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
  cloneable = FALSE,
  public = list(
    #' @description Start a new SecureSessionPool
    #' @param size Integer, number of sessions to start (default 4, minimum 1).
    #' @param tools A list of [securer_tool()] objects passed to each session.
    #' @param sandbox Logical, whether to use the OS sandbox.
    #' @param limits Optional named list of resource limits.
    #' @param verbose Logical, whether to print what each session is doing.
    #' @param reset_between_uses Logical, whether to restart each session
    #'   before it goes back to the pool (default `FALSE`). With `TRUE`, the
    #'   pool calls `session$restart()` after every `$execute()`, so
    #'   variables, loaded packages, and options from one run don't carry
    #'   over to the next.
    initialize = function(size = 4L, tools = list(), sandbox = TRUE,
                          limits = NULL, verbose = FALSE,
                          reset_between_uses = FALSE) {
      size <- as.integer(size)
      if (size < 1L) {
        cli::cli_abort(
          "{.arg size} must be at least {.val {1L}}, not {.val {size}}.",
          call = NULL
        )
      }
      if (size > 100L) {
        cli::cli_abort(
          "{.arg size} must not exceed {.val {100L}}, got {.val {size}}.",
          call = NULL
        )
      }

      private$pool_tools <- tools
      private$pool_sandbox <- sandbox
      private$pool_limits <- limits
      private$pool_verbose <- verbose
      private$pool_reset <- reset_between_uses
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

    #' @description Run R code on an idle session from the pool
    #' @param code Character string of R code to execute.
    #' @param timeout Timeout in seconds, or `NULL` for no timeout.
    #' @param acquire_timeout Optional number of seconds to wait for a free
    #'   session. If `NULL` (the default), the call fails straight away when
    #'   every session is busy. Otherwise the pool keeps trying, every 0.1
    #'   seconds, until the time is up.
    #' @return The value of the last expression in `code`.
    execute = function(code, timeout = NULL, acquire_timeout = NULL) {
      if (private$closed) {
        cli::cli_abort("Pool is closed.", call = NULL)
      }

      idx <- private$acquire()

      # If no session available and acquire_timeout is set, retry with backoff
      if (is.null(idx) && !is.null(acquire_timeout)) {
        deadline <- Sys.time() + acquire_timeout
        while (is.null(idx) && Sys.time() < deadline) {
          Sys.sleep(0.1)
          idx <- private$acquire()
        }
      }

      if (is.null(idx)) {
        cli::cli_abort("All sessions are busy.", call = NULL)
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

    #' @description Number of idle sessions
    #' @return Integer
    available = function() {
      if (private$closed) return(0L)
      sum(!private$busy)
    },

    #' @description Count sessions by state
    #' @return A named list with `total`, `busy`, `idle`, and `dead` counts.
    #'   `dead` counts sessions whose process has stopped and that need a
    #'   restart.
    status = function() {
      if (private$closed) {
        return(list(total = 0L, busy = 0L, idle = 0L, dead = 0L))
      }
      n_total <- length(private$sessions)
      n_busy <- sum(private$busy)
      # Check which sessions are alive
      alive <- vapply(private$sessions, function(s) s$is_alive(), logical(1))
      n_dead <- sum(!alive)
      # Idle = not busy AND alive
      n_idle <- sum(!private$busy & alive)
      list(total = n_total, busy = n_busy, idle = n_idle, dead = n_dead)
    },

    #' @description Format the pool for printing
    #' @param ... Ignored.
    #' @return A character string describing the pool.
    format = function(...) {
      if (private$closed) {
        return("<SecureSessionPool> [closed]")
      }
      n_total <- length(private$sessions)
      n_busy <- sum(private$busy)
      n_idle <- n_total - n_busy
      sprintf("<SecureSessionPool> size=%d idle=%d busy=%d",
              n_total, n_idle, n_busy)
    },

    #' @description Print method
    #' @param ... Ignored.
    #' @return Invisible self.
    print = function(...) {
      if (private$closed) {
        cli::cli_text("<{.cls SecureSessionPool}> [closed]")
      } else {
        n_total <- length(private$sessions)
        n_busy <- sum(private$busy)
        n_idle <- n_total - n_busy
        cli::cli_text("<{.cls SecureSessionPool}>")
        cli::cli_ul(c(
          "Pool size: {n_total}",
          "Active: {n_busy}",
          "Idle: {n_idle}"
        ))
      }
      invisible(self)
    },

    #' @description Close every session in the pool
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
    pool_reset = FALSE,

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
      if (private$pool_reset) {
        tryCatch(
          private$sessions[[idx]]$restart(),
          error = function(e) NULL
        )
      }
      private$busy[[idx]] <- FALSE
    }
  )
)
