#' Build Docker container-spawning sandbox configuration
#'
#' Spawns the child R process inside a fresh Docker container instead of
#' running it natively.  The wrapper script invokes `docker run` with
#' `--network=none`, memory/CPU caps, and a bind mount of the UDS socket
#' directory so the child can connect back to the parent.  This provides
#' stronger isolation than the in-Docker backend (which assumes the session
#' itself is already inside a container) at the cost of docker startup
#' latency.
#'
#' Activated by setting `SECURER_SANDBOX_MODE=docker-spawn`.  The image
#' defaults to `rocker/r-base:latest` but can be overridden via
#' `SECURER_DOCKER_IMAGE`.  The bind-mount directory defaults to the socket
#' path's parent directory (usually `/tmp`) and can be overridden via
#' `SECURER_DOCKER_MOUNT`.
#'
#' The backend gates at runtime on `docker --version`; if docker is not
#' available the dispatcher in [build_sandbox_config()] falls through to
#' the next backend.
#'
#' @param socket_path Path to the UDS socket (must live in the mount dir)
#' @param r_home      Path to the R installation (unused; R comes from the
#'   container image)
#' @param limits      Optional named list of resource limits.  `memory` and
#'   `cpu` are mapped to docker flags; other keys become ulimit commands
#'   applied inside the container.
#' @return A sandbox config list (see [build_sandbox_config()])
#' @keywords internal
build_sandbox_docker_spawn <- function(socket_path, r_home, limits = NULL) {
  image <- Sys.getenv("SECURER_DOCKER_IMAGE", unset = "rocker/r-base:latest")
  mount_dir <- Sys.getenv(
    "SECURER_DOCKER_MOUNT",
    unset = dirname(socket_path)
  )

  memory_flag <- ""
  cpu_flag <- ""
  ulimit_cmds <- character(0)
  if (!is.null(limits) && length(limits) > 0) {
    validate_limits(limits)
    if (!is.null(limits$memory)) {
      memory_flag <- sprintf(" --memory=%db", as.integer(limits$memory))
    }
    if (!is.null(limits$cpu)) {
      cpu_flag <- sprintf(" --cpus=%s", format(limits$cpu / 60, nsmall = 2))
    }
    ulimit_only <- limits[setdiff(names(limits), c("memory", "cpu"))]
    ulimit_cmds <- generate_ulimit_commands(ulimit_only)
  }

  wrapper_path <- tempfile("securer_docker_spawn_", fileext = ".sh")
  docker_cmd <- sprintf(
    paste0(
      'exec docker run --rm -i --network=none%s%s',
      ' -v %s:%s',
      ' %s R "$@"'
    ),
    memory_flag,
    cpu_flag,
    shQuote(mount_dir),
    shQuote(mount_dir),
    shQuote(image)
  )
  writeLines(
    c("#!/bin/sh", ulimit_cmds, docker_cmd),
    wrapper_path
  )
  Sys.chmod(wrapper_path, "0700")

  list(
    wrapper      = wrapper_path,
    profile_path = NULL
  )
}

#' Check whether the docker CLI and daemon are reachable
#'
#' @return `TRUE` if `docker info` succeeds, `FALSE` otherwise.
#' @keywords internal
is_docker_spawn_available <- function() {
  if (!nzchar(Sys.which("docker"))) return(FALSE)
  status <- suppressWarnings(
    system2("docker", "info", stdout = FALSE, stderr = FALSE)
  )
  identical(status, 0L)
}
