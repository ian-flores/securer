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
