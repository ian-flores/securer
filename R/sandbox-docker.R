#' Build in-container Docker sandbox configuration
#'
#' Used when the securer session is *already running inside* a Docker
#' container.  The container itself provides filesystem and network
#' isolation, so this builder skips bubblewrap (which requires namespace
#' support Docker typically doesn't expose) and applies only resource
#' limits (`ulimit`) via a wrapper script.
#'
#' This is **not** the same as [build_sandbox_docker_spawn()], which
#' *spawns* a fresh container for each child session.  This backend is
#' activated automatically when `/.dockerenv` exists, or manually by
#' setting `SECURER_SANDBOX_MODE=docker`.  The container-spawning backend
#' is activated by `SECURER_SANDBOX_MODE=docker-spawn`.
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @param limits      Optional named list of resource limits (see
#'   `generate_ulimit_commands()`)
#' @return A sandbox config list (see [build_sandbox_config()])
#' @keywords internal
build_sandbox_docker <- function(socket_path, r_home, limits = NULL) {
  ulimit_cmds <- generate_ulimit_commands(limits)

  r_bin <- file.path(r_home, "bin", "R")
  wrapper_path <- tempfile("securer_r_", fileext = ".sh")
  writeLines(c(
    "#!/bin/sh",
    ulimit_cmds,
    sprintf('exec "%s" "$@"', r_bin)
  ), wrapper_path)
  Sys.chmod(wrapper_path, "0700")

  list(
    wrapper      = wrapper_path,
    profile_path = NULL
  )
}
