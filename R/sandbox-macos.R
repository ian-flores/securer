#' Generate a macOS Seatbelt profile for the sandboxed R session
#'
#' Creates a Seatbelt policy string that:
#' \itemize{
#'   \item Denies all operations by default
#'   \item Allows file reads only for R installation, library paths, system
#'     libraries, and temp directories (blocks ~/.ssh, ~/.env, etc.)
#'   \item Allows file writes only to the temp directory (for UDS + R temp files)
#'   \item Allows Unix domain socket operations (IPC with the parent)
#'   \item Denies remote network access (TCP/UDP)
#'   \item Allows only process-fork and process-exec for the R binary
#'   \item Allows only specific system operations R needs
#' }
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @param lib_paths   Character vector of R library paths (default: `.libPaths()`)
#' @return A single character string containing the Seatbelt profile
#' @keywords internal
generate_seatbelt_profile <- function(socket_path, r_home,
                                      lib_paths = .libPaths()) {
  tmp_dir <- dirname(socket_path)

  # Determine the current user's /private/var/folders/XX/YYYYYY path
  # so we can scope read/write rules to just this user's temp area.
  user_var_folder <- NULL
  tmpdir_val <- normalizePath(
    Sys.getenv("TMPDIR", tempdir()),
    mustWork = FALSE
  )
  var_folder_match <- regmatches(
    tmpdir_val,
    regexpr("/private/var/folders/[^/]+/[^/]+", tmpdir_val)
  )
  if (length(var_folder_match) == 1 && nzchar(var_folder_match)) {
    user_var_folder <- var_folder_match
  }

  # Build explicit file-read rules for each R library path.
  # Deduplicate and exclude paths already covered by r_home.
  lib_read_rules <- character(0)
  for (lp in unique(lib_paths)) {
    # Skip if already under r_home (will be covered by the r_home subpath rule)
    if (!startsWith(lp, r_home)) {
      lib_read_rules <- c(
        lib_read_rules,
        sprintf('(allow file-read* (subpath "%s"))', lp)
      )
    }
  }
  lib_read_section <- paste(lib_read_rules, collapse = "\n")

  # R bin directory for process-exec restriction.
  # R startup chain: bin/R (shell script) -> bin/exec/R (actual binary).
  # Allow exec of anything under R's bin/ directory to cover both.
  r_bin_dir <- file.path(r_home, "bin")

  # Build process-exec rules
  exec_rules <- sprintf('(allow process-exec (subpath "%s"))', r_bin_dir)

  paste0(
    '(version 1)
(deny default)

;; -- File access (reads) ----------------------------------------------
;; Allow file-read-metadata globally (stat, readdir for path traversal).
;; This reveals file existence/size but NOT contents.
(allow file-read-metadata)

;; Allow reading root directory listing (shell needs this for path resolution)
(allow file-read-data (literal "/"))
(allow file-read-data (literal "/private"))

;; R installation (R.home())
(allow file-read* (subpath "', r_home, '"))

;; R library paths (.libPaths() outside R.home())
', lib_read_section, '

;; System libraries, frameworks, and shared objects
(allow file-read* (subpath "/usr"))
(allow file-read* (subpath "/Library/Frameworks"))
(allow file-read* (subpath "/System/Library"))
(allow file-read* (subpath "/opt/homebrew/lib"))
(allow file-read* (subpath "/opt/homebrew/Cellar"))
(allow file-read* (subpath "/opt/homebrew/opt"))
(allow file-read* (subpath "/bin"))

;; Device nodes R needs (specific devices, not all of /dev)
(allow file-read* (literal "/dev/null"))
(allow file-read* (literal "/dev/random"))
(allow file-read* (literal "/dev/urandom"))
(allow file-read* (literal "/dev/tty"))
(allow file-read* (literal "/dev/zero"))
(allow file-read* (literal "/dev/stdin"))
(allow file-read* (literal "/dev/stdout"))
(allow file-read* (literal "/dev/stderr"))
(allow file-read* (literal "/dev/fd"))
(allow file-read* (subpath "/dev/fd"))

;; Selective /etc reads (only what R needs)
(allow file-read* (literal "/etc/localtime"))
(allow file-read* (literal "/private/etc/localtime"))
(allow file-read* (literal "/etc/resolv.conf"))
(allow file-read* (literal "/private/etc/resolv.conf"))
(allow file-read* (subpath "/etc/ssl"))
(allow file-read* (subpath "/private/etc/ssl"))
(allow file-read* (literal "/etc/hosts"))
(allow file-read* (literal "/private/etc/hosts"))
(allow file-read* (subpath "/etc/pki"))
(allow file-read* (subpath "/private/etc/pki"))

;; Temp and cache directories
(allow file-read* (subpath "/tmp"))
(allow file-read* (subpath "/private/tmp"))
', if (!is.null(user_var_folder)) {
    paste0(
      '(allow file-read* (subpath "', user_var_folder, '"))\n',
      '(allow file-read* (subpath "',
      sub("^/private", "", user_var_folder), '"))'
    )
  } else {
    paste0(
      '(allow file-read* (regex #"^/private/var/folders/"))\n',
      '(allow file-read* (regex #"^/var/folders/"))'
    )
  }, '

;; Seatbelt profile itself (sandbox-exec needs to read it)
(allow file-read* (subpath "', tmp_dir, '"))

;; -- File access (writes) ---------------------------------------------
;; Allow writes ONLY to the session-specific socket directory and R temp
;; directories.  Blocks writes to other sessions or other apps in /tmp.
(allow file-write* (subpath "', tmp_dir, '"))
', if (!is.null(user_var_folder)) {
    paste0(
      '(allow file-write* (subpath "', user_var_folder, '"))\n',
      '(allow file-write* (subpath "',
      sub("^/private", "", user_var_folder), '"))'
    )
  } else {
    paste0(
      '(allow file-write* (regex #"^/private/var/folders/"))\n',
      '(allow file-write* (regex #"^/var/folders/"))'
    )
  }, '
(allow file-write* (literal "/dev/null"))
(allow file-write* (literal "/dev/tty"))
(allow file-write* (literal "/dev/random"))
(allow file-write* (literal "/dev/urandom"))

;; -- Network ----------------------------------------------------------
;; Allow local Unix domain sockets (our IPC mechanism).
(allow network* (local unix))

;; DENY all remote IP network access (TCP and UDP).
(deny network* (remote ip))

;; -- Process ----------------------------------------------------------
;; Allow fork and exec of R binaries (bin/R script + bin/exec/R binary).
;; Allow core POSIX utilities needed by R startup script (sed, grep, etc.).
;; Blocks execution of interpreters (python, perl, ruby, etc.).
(allow process-fork)
', exec_rules, '
(allow process-exec (literal "/bin/sh"))
(allow process-exec (literal "/bin/rm"))
(allow process-exec (literal "/usr/bin/sed"))
(allow process-exec (literal "/usr/bin/uname"))
(allow process-exec (literal "/usr/bin/grep"))
(allow process-exec (literal "/usr/bin/dirname"))
(allow process-exec (literal "/usr/bin/basename"))

;; -- Mach / IPC -------------------------------------------------------
;; R needs mach lookups for system services, dyld, etc.
(allow sysctl-read)
(allow mach-lookup)
(allow mach-priv-host-port)
(allow signal (target self))
(allow ipc-posix*)
(allow iokit-open)

;; -- System -----------------------------------------------------------
;; Only allow specific system operations R needs, not blanket system*.
(allow system-socket)
(allow system-fsctl)
(allow system-info)
')
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
#' @param limits      Optional named list of resource limits (see
#'   `generate_ulimit_commands()`)
#' @return A sandbox config list (see [build_sandbox_config()])
#' @keywords internal
build_sandbox_macos <- function(socket_path, r_home, limits = NULL) {
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
  Sys.chmod(profile_path, "0600")

  # Determine the real R binary path

  r_bin <- file.path(r_home, "bin", "R")

  # Build ulimit commands for resource limits
  ulimit_cmds <- generate_ulimit_commands(limits)

  # Create a thin wrapper script that execs sandbox-exec around R
  wrapper_path <- tempfile("securer_r_", fileext = ".sh")
  writeLines(c(
    "#!/bin/sh",
    ulimit_cmds,
    sprintf(
      'exec /usr/bin/sandbox-exec -f "%s" "%s" "$@"',
      profile_path, r_bin
    )
  ), wrapper_path)
  Sys.chmod(wrapper_path, "0700")

  list(
    wrapper      = wrapper_path,
    profile_path = profile_path
  )
}
