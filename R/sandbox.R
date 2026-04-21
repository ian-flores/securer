#' Build sandbox configuration for the current platform
#'
#' Inspects the operating system and delegates to the appropriate platform-
#' specific sandbox builder.  Returns a list that `start_session()` uses to
#' wrap the child R process.
#'
#' @param socket_path Path to the UDS socket (must be writable by the child)
#' @param r_home      Path to the R installation (default: `R.home()`)
#' @param limits      Optional named list of resource limits (see
#'   `generate_ulimit_commands()`)
#' @return A list with elements:
#'   \describe{
#'     \item{wrapper}{Path to a shell wrapper script, or `NULL`}
#'     \item{profile_path}{Path to the generated sandbox profile, or `NULL`}
#'   }
#' @keywords internal
build_sandbox_config <- function(socket_path, r_home = R.home(),
                                 limits = NULL) {
  # Explicit docker-spawn mode: launch a fresh container per session.
  if (identical(Sys.getenv("SECURER_SANDBOX_MODE"), "docker-spawn") &&
      is_docker_spawn_available()) {
    return(build_sandbox_docker_spawn(socket_path, r_home, limits = limits))
  }

  # In-container detection: the session itself is already in docker, so the
  # container provides filesystem/network isolation and we skip bwrap.
  if (file.exists("/.dockerenv") ||
      identical(Sys.getenv("SECURER_SANDBOX_MODE"), "docker")) {
    return(build_sandbox_docker(socket_path, r_home, limits = limits))
  }

  os <- tolower(Sys.info()[["sysname"]])
  switch(os,
    darwin  = build_sandbox_macos(socket_path, r_home, limits = limits),
    linux   = build_sandbox_linux(socket_path, r_home, limits = limits),
    windows = build_sandbox_windows(socket_path, r_home, limits = limits),
    build_sandbox_fallback(socket_path, r_home)
  )
}
