#' Build Windows sandbox configuration
#'
#' True OS-level sandboxing is not available on Windows without admin
#' privileges (would require Windows Job Objects / AppContainers).
#' This function raises an error when called, directing users to either
#' use `sandbox = FALSE` with explicit resource limits, or run inside
#' a container for real isolation.
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return Never returns; always raises an error.
#' @keywords internal
build_sandbox_windows <- function(socket_path, r_home) {
  stop(
    "True OS-level sandboxing is not available on Windows. ",
    "Use sandbox = FALSE with explicit resource limits, or run in a ",
    "Docker container for isolation. See ?SecureSession for details.",
    call. = FALSE
  )
}
