#' Build sandbox configuration for the current platform
#'
#' Inspects the operating system and delegates to the appropriate platform-
#' specific sandbox builder.  Returns a list that `start_session()` uses to
#' wrap the child R process.
#'
#' @param socket_path Path to the UDS socket (must be writable by the child)
#' @param r_home      Path to the R installation (default: `R.home()`)
#' @param limits      Optional named list of resource limits (see
#'   [generate_ulimit_commands()])
#' @return A list with elements:
#'   \describe{
#'     \item{wrapper}{Path to a shell wrapper script, or `NULL`}
#'     \item{profile_path}{Path to the generated sandbox profile, or `NULL`}
#'   }
#' @keywords internal
build_sandbox_config <- function(socket_path, r_home = R.home(),
                                 limits = NULL) {
  os <- tolower(Sys.info()[["sysname"]])
  switch(os,
    darwin  = build_sandbox_macos(socket_path, r_home, limits = limits),
    linux   = build_sandbox_linux(socket_path, r_home, limits = limits),
    windows = build_sandbox_windows(socket_path, r_home),
    build_sandbox_fallback(socket_path, r_home)
  )
}
