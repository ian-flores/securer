#' Generate bubblewrap CLI arguments for the sandboxed R session
#'
#' Creates a character vector of `bwrap` arguments that:
#' \itemize{
#'   \item Isolates all namespaces (PID, net, user, mount, UTS, IPC)
#'   \item Bind-mounts system libraries and R read-only
#'   \item Provides a clean writable `/tmp` with the UDS socket overlaid
#'   \item Blocks all network access via namespace isolation
#' }
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return A character vector of bwrap CLI arguments
#' @keywords internal
generate_bwrap_args <- function(socket_path, r_home) {
  socket_dir <- dirname(socket_path)

  args <- c(
    # -- Namespace isolation ---------------------------------------------------
    "--unshare-all",
    "--die-with-parent",
    "--new-session",

    # -- System libraries (read-only) -----------------------------------------
    "--ro-bind", "/usr", "/usr",
    "--ro-bind", "/lib", "/lib",
    "--ro-bind-try", "/lib64", "/lib64",
    "--ro-bind-try", "/bin", "/bin",
    "--ro-bind-try", "/sbin", "/sbin",

    # -- Config files ----------------------------------------------------------
    "--ro-bind-try", "/etc/ld.so.cache", "/etc/ld.so.cache",
    "--ro-bind-try", "/etc/ld.so.conf", "/etc/ld.so.conf",
    "--ro-bind-try", "/etc/ld.so.conf.d", "/etc/ld.so.conf.d",
    "--ro-bind-try", "/etc/localtime", "/etc/localtime",
    "--ro-bind-try", "/etc/ssl", "/etc/ssl",
    "--ro-bind-try", "/etc/pki", "/etc/pki",
    "--ro-bind-try", "/etc/R", "/etc/R",

    # -- R installation --------------------------------------------------------
    "--ro-bind", r_home, r_home,

    # -- Pseudo-filesystems ----------------------------------------------------
    "--proc", "/proc",
    "--dev", "/dev",

    # -- Mask sensitive /proc entries ------------------------------------------
    # /proc/self/environ exposes all environment variables (including any
    # secrets that weren't unset before reaching this point).
    # /proc/self/maps reveals the memory layout, which aids ASLR bypass.
    # /proc/self/fd/ reveals open file descriptors including the UDS socket,
    # which could be used to directly write raw IPC messages.
    # We mask these with empty tmpfs mounts.
    "--tmpfs", "/proc/self/environ",
    "--tmpfs", "/proc/self/maps",
    "--tmpfs", "/proc/self/fd",

    # -- Writable temp (clean) -------------------------------------------------
    "--tmpfs", "/tmp",

    # -- UDS socket dir (overlays /tmp, must come after --tmpfs) ----------------
    "--bind", socket_dir, socket_dir,

    # -- Environment -----------------------------------------------------------
    "--setenv", "HOME", "/tmp",
    "--setenv", "TMPDIR", "/tmp",
    "--setenv", "LANG", "C.UTF-8",
    "--setenv", "TZ", "UTC",
    "--setenv", "R_LIBS_USER", "",
    "--setenv", "SECURER_SOCKET", socket_path
  )

  # Add R package library paths (may not be under /usr or r_home)
  lib_paths <- .libPaths()
  for (lp in lib_paths) {
    # Normalise to avoid duplicates with r_home
    lp <- normalizePath(lp, mustWork = FALSE)
    if (!startsWith(lp, r_home) && !startsWith(lp, "/usr")) {
      args <- c(args, "--ro-bind-try", lp, lp)
    }
  }

  args
}

#' Build Linux sandbox configuration
#'
#' Locates `bwrap` (bubblewrap) and creates a wrapper shell script that
#' launches R inside a fully-isolated sandbox.  The wrapper can be passed to
#' [callr::r_session_options()] via the `arch` parameter.
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @param limits      Optional named list of resource limits (see
#'   `generate_ulimit_commands()`)
#' @return A sandbox config list (see [build_sandbox_config()])
#' @keywords internal
build_sandbox_linux <- function(socket_path, r_home, limits = NULL) {
  bwrap_path <- Sys.which("bwrap")
  if (!nzchar(bwrap_path)) {
    warning(
      "bwrap (bubblewrap) not found; falling back to unsandboxed session",
      call. = FALSE
    )
    return(build_sandbox_fallback(socket_path, r_home))
  }

  bwrap_args <- generate_bwrap_args(socket_path, r_home)

  # Determine the R binary path
  r_bin <- file.path(r_home, "bin", "R")

  # Build ulimit commands for resource limits
  ulimit_cmds <- generate_ulimit_commands(limits)

  # Create wrapper script: ulimit commands then exec bwrap <args> -- R "$@"
  wrapper_path <- tempfile("securer_r_", fileext = ".sh")
  args_str <- paste(shQuote(bwrap_args), collapse = " ")
  writeLines(c(
    "#!/bin/sh",
    ulimit_cmds,
    sprintf(
      'exec %s %s -- %s "$@"',
      shQuote(bwrap_path), args_str, shQuote(r_bin)
    )
  ), wrapper_path)
  Sys.chmod(wrapper_path, "0700")

  list(
    wrapper      = wrapper_path,
    profile_path = NULL
  )
}
