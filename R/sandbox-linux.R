#' Build Linux sandbox configuration (stub)
#'
#' Linux sandbox using bubblewrap (`bwrap`) with namespace isolation,
#' read-only bind-mounts, and network denial.
#'
#' **Not yet implemented** -- falls back to [build_sandbox_fallback()].
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return A sandbox config list (see [build_sandbox_config()])
#' @keywords internal
build_sandbox_linux <- function(socket_path, r_home) {
  warning(
    "Linux sandbox (bwrap) is not yet implemented; ",
    "session will run without sandboxing",
    call. = FALSE
  )
  list(
    wrapper      = NULL,
    profile_path = NULL
  )
}
