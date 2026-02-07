#' Build fallback sandbox configuration (no OS sandbox)
#'
#' Used when no platform-specific sandbox is available.  Returns a config
#' with `NULL` wrapper and profile so the session starts without any OS-level
#' isolation.
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return A sandbox config list with `wrapper = NULL` and
#'   `profile_path = NULL`
#' @keywords internal
build_sandbox_fallback <- function(socket_path, r_home) {
  warning(
    "OS-level sandbox not available on this platform; ",
    "session will run without sandboxing",
    call. = FALSE
  )
  list(
    wrapper      = NULL,
    profile_path = NULL
  )
}
