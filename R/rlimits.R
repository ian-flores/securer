#' Default resource limits for sandboxed sessions
#'
#' Returns the default resource limits that are applied automatically when
#' `sandbox = TRUE` and no explicit `limits` are provided to
#' [SecureSession] or [execute_r()].  Useful for inspecting the defaults
#' and creating custom limits based on them.
#'
#' The returned list contains:
#' \describe{
#'   \item{cpu}{CPU time limit in seconds (default: 60).}
#'   \item{memory}{Virtual memory limit in bytes (default: 512 MB).}
#'   \item{fsize}{Maximum file size in bytes (default: 50 MB).}
#'   \item{nproc}{Maximum number of child processes (default: 50).}
#'   \item{nofile}{Maximum number of open file descriptors (default: 256).}
#' }
#'
#' You can pass a modified copy to `SecureSession$new(limits = ...)` or
#' `execute_r(limits = ...)`.  Pass `limits = list()` to explicitly
#' disable all resource limits.
#'
#' @return A named list of resource limits.
#'
#' @examples
#' # Inspect defaults
#' default_limits()
#'
#' # Double the memory limit
#' my_limits <- default_limits()
#' my_limits$memory <- 1024 * 1024 * 1024  # 1 GB
#'
#' @export
default_limits <- function() {
  list(
    cpu    = 60,                    # 60 seconds CPU time
    memory = 512 * 1024 * 1024,    # 512 MB virtual memory
    fsize  = 50 * 1024 * 1024,     # 50 MB max file size
    nproc  = 50,                   # 50 child processes max
    nofile = 256                   # 256 open file descriptors
  )
}

#' Generate ulimit shell commands from a limits list
#'
#' Translates a user-facing limits list into shell `ulimit` commands that
#' can be injected into wrapper scripts before the `exec` line.
#'
#' Supported limit names:
#' \describe{
#'   \item{cpu}{CPU time in seconds (`ulimit -t`)}
#'   \item{memory}{Virtual memory (address space) in bytes (`ulimit -v`).
#'     Converted to kilobytes for ulimit.}
#'   \item{fsize}{Maximum file size in bytes (`ulimit -f`).
#'     Converted to 512-byte blocks for ulimit.}
#'   \item{nproc}{Maximum number of processes (`ulimit -u`)}
#'   \item{nofile}{Maximum number of open files (`ulimit -n`)}
#'   \item{stack}{Maximum stack size in bytes (`ulimit -s`).
#'     Converted to kilobytes for ulimit.}
#' }
#'
#' @param limits A named list of resource limits, or `NULL` for no limits.
#' @return A character vector of shell commands (one per limit), or
#'   `character(0)` if `limits` is `NULL` or empty.
#' @keywords internal
generate_ulimit_commands <- function(limits) {
  if (is.null(limits) || length(limits) == 0) {
    return(character(0))
  }

  validate_limits(limits)

  # Mapping from user-facing names to ulimit flags and unit conversions
  limit_map <- list(
    cpu    = list(flag = "-t", divisor = 1),       # seconds
    memory = list(flag = "-v", divisor = 1024),    # bytes -> KB
    fsize  = list(flag = "-f", divisor = 512),     # bytes -> 512-byte blocks
    nproc  = list(flag = "-u", divisor = 1),       # count
    nofile = list(flag = "-n", divisor = 1),       # count
    stack  = list(flag = "-s", divisor = 1024)     # bytes -> KB
  )

  cmds <- character(0)
  for (name in names(limits)) {
    spec <- limit_map[[name]]
    value <- as.integer(ceiling(limits[[name]] / spec$divisor))
    cmds <- c(cmds, sprintf("ulimit -S -H %s %d", spec$flag, value))
  }

  cmds
}

#' Validate a limits list
#'
#' Checks that all limit names are recognized and all values are positive
#' numbers.
#'
#' @param limits A named list of resource limits.
#' @return Invisible `NULL`; raises an error on invalid input.
#' @keywords internal
validate_limits <- function(limits) {
  valid_names <- c("cpu", "memory", "fsize", "nproc", "nofile", "stack")

  unknown <- setdiff(names(limits), valid_names)
  if (length(unknown) > 0) {
    stop(
      "Unknown limit name(s): ", paste(unknown, collapse = ", "),
      ". Valid names: ", paste(valid_names, collapse = ", "),
      call. = FALSE
    )
  }

  for (name in names(limits)) {
    val <- limits[[name]]
    if (!is.numeric(val) || length(val) != 1 || val <= 0) {
      stop(
        "Limit '", name, "' must be a single positive number, got: ",
        deparse(val),
        call. = FALSE
      )
    }
  }

  invisible(NULL)
}

#' Build a minimal wrapper script that only applies resource limits
#'
#' Used when `sandbox = FALSE` but `limits` is provided.  Creates a shell
#' wrapper that sets ulimit values and then `exec`s R.
#'
#' @param limits A named list of resource limits.
#' @return A sandbox config list with `wrapper` and `profile_path = NULL`.
#' @keywords internal
build_limits_only_wrapper <- function(limits) {
  ulimit_cmds <- generate_ulimit_commands(limits)
  if (length(ulimit_cmds) == 0) {
    return(list(wrapper = NULL, profile_path = NULL))
  }

  r_bin <- file.path(R.home(), "bin", "R")
  wrapper_path <- tempfile("securer_r_", fileext = ".sh")
  writeLines(c(
    "#!/bin/sh",
    ulimit_cmds,
    sprintf('exec "%s" "$@"', r_bin)
  ), wrapper_path)
  Sys.chmod(wrapper_path, "0755")

  list(
    wrapper      = wrapper_path,
    profile_path = NULL
  )
}

#' Windows-supported resource limit names
#'
#' Returns the limit names that can be enforced on Windows via Job Objects.
#' @return A character vector of supported limit names.
#' @keywords internal
windows_supported_limits <- function() {
  c("cpu", "memory", "nproc")
}
