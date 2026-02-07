#' Build Windows sandbox configuration
#'
#' Provides environment-variable-only isolation for Windows.
#' Windows lacks an unprivileged lightweight sandbox comparable to macOS Seatbelt
#' or Linux bubblewrap, so this implementation sets restrictive environment
#' variables to limit the child R process.  Specifically:
#' \itemize{
#'   \item Sets `R_LIBS_USER` to empty, preventing user-installed packages
#'   \item Sets `HOME` and `TMPDIR` to a clean temporary directory
#'   \item Sets `R_USER` to match the clean temp directory
#'   \item Clears `R_ENVIRON_USER` and `R_PROFILE_USER` to prevent
#'         user startup code from executing
#' }
#'
#' **Important:** This does NOT enforce filesystem or network restrictions.
#' Any code running in the child process can still access the filesystem and
#' network without restriction.  For true sandboxing on Windows, admin
#' privileges and Windows Job Objects / AppContainers would be required.
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return A sandbox config list with:
#'   \describe{
#'     \item{wrapper}{`NULL` (no wrapper script on Windows)}
#'     \item{profile_path}{`NULL` (no sandbox profile on Windows)}
#'     \item{env}{Named character vector of restrictive environment variables
#'       to pass to [callr::r_session_options()]}
#'   }
#' @keywords internal
build_sandbox_windows <- function(socket_path, r_home) {
  warning(
    "Windows sandbox provides environment isolation only (no filesystem ",
    "or network restrictions). For stronger sandboxing, use macOS or Linux.",
    call. = FALSE
  )

  # Create a clean temporary directory for the child process
  sandbox_tmp <- tempfile("securer_sandbox_")
  dir.create(sandbox_tmp, recursive = TRUE)

  env <- c(
    R_LIBS_USER     = "",
    HOME            = sandbox_tmp,
    TMPDIR          = sandbox_tmp,
    TMP             = sandbox_tmp,
    TEMP            = sandbox_tmp,
    R_USER          = sandbox_tmp,
    R_ENVIRON_USER  = "",
    R_PROFILE_USER  = ""
  )

  list(
    wrapper      = NULL,
    profile_path = NULL,
    sandbox_tmp  = sandbox_tmp,
    env          = env
  )
}
