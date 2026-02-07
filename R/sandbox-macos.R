#' Generate a macOS Seatbelt profile for the sandboxed R session
#'
#' Creates a Seatbelt policy string that:
#' \itemize{
#'   \item Denies all operations by default
#'   \item Allows file reads everywhere (low risk, needed for R + packages)
#'   \item Allows file writes only to the temp directory (for UDS + R temp files)
#'   \item Allows Unix domain socket operations (IPC with the parent)
#'   \item Denies remote network access (TCP/UDP)
#'   \item Allows process, mach, sysctl, and signal operations needed by R
#' }
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return A single character string containing the Seatbelt profile
#' @keywords internal
generate_seatbelt_profile <- function(socket_path, r_home) {
  tmp_dir <- dirname(socket_path)

  sprintf(
    '(version 1)
(deny default)

;; -- File access ------------------------------------------------------
;; Allow reading everywhere.  Reads are low-risk and R needs access to
;; system libraries, frameworks, locale data, the R installation, and
;; every package directory on .libPaths().
(allow file-read*)

;; Allow writes ONLY to temp directories (UDS socket + R session temp
;; files live here) and /dev/null (R startup writes to it).
(allow file-write* (subpath "/tmp"))
(allow file-write* (subpath "/private/tmp"))
(allow file-write* (regex #"^/private/var/folders/"))
(allow file-write* (regex #"^/var/folders/"))
(allow file-write* (literal "/dev/null"))
(allow file-write* (literal "/dev/tty"))
(allow file-write* (literal "/dev/random"))
(allow file-write* (literal "/dev/urandom"))
(allow file-write* (subpath "%s"))

;; -- Network ----------------------------------------------------------
;; Allow local Unix domain sockets (our IPC mechanism).
(allow network* (local unix))

;; DENY all remote IP network access (TCP and UDP).
(deny network* (remote ip))

;; -- Process / system -------------------------------------------------
;; R needs to exec, fork, look up mach services, read sysctl, etc.
(allow process*)
(allow sysctl*)
(allow mach*)
(allow signal)
(allow ipc-posix*)
(allow iokit*)
(allow system*)
',
    tmp_dir
  )
}

#' Build macOS sandbox configuration
#'
#' Writes a temporary Seatbelt profile and creates a wrapper shell script
#' that launches R inside `sandbox-exec`.  The wrapper can be passed to
#' [callr::r_session_options()] via the `arch` parameter (which callr
#' uses as the path to the R binary).
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @return A sandbox config list (see [build_sandbox_config()])
#' @keywords internal
build_sandbox_macos <- function(socket_path, r_home) {
  if (!file.exists("/usr/bin/sandbox-exec")) {
    warning(
      "sandbox-exec not found; falling back to unsandboxed session",
      call. = FALSE
    )
    return(build_sandbox_fallback(socket_path, r_home))
  }

  # Generate and write the Seatbelt profile

  profile_content <- generate_seatbelt_profile(socket_path, r_home)
  profile_path <- tempfile("securer_sb_", fileext = ".sb")
  writeLines(profile_content, profile_path)

  # Determine the real R binary path

  r_bin <- file.path(r_home, "bin", "R")

  # Create a thin wrapper script that execs sandbox-exec around R
  wrapper_path <- tempfile("securer_r_", fileext = ".sh")
  writeLines(c(
    "#!/bin/sh",
    sprintf(
      'exec /usr/bin/sandbox-exec -f "%s" "%s" "$@"',
      profile_path, r_bin
    )
  ), wrapper_path)
  Sys.chmod(wrapper_path, "0755")

  list(
    wrapper      = wrapper_path,
    profile_path = profile_path
  )
}
