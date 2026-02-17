# Test helpers for securer

#' Skip tests that spawn child processes (sessions, pools, execute_r)
#' These are too resource-intensive for CRAN check servers.
skip_if_no_session <- function() {
  skip_on_cran()
}

#' Check if sandbox-exec can actually launch R with our profile.
#' On some CI runners the Seatbelt profile doesn't have the right paths
#' for the runner's R installation layout.
sandbox_exec_works <- function() {
  if (!file.exists("/usr/bin/sandbox-exec")) return(FALSE)
  tryCatch({
    session <- SecureSession$new(sandbox = TRUE)
    session$close()
    TRUE
  }, error = function(e) FALSE)
}

#' Check if bwrap can actually create namespaces (fails in containers)
bwrap_works <- function() {
  bwrap <- Sys.which("bwrap")
  if (!nzchar(bwrap)) return(FALSE)
  res <- tryCatch(
    processx::run(bwrap, c("--unshare-all", "--ro-bind", "/usr", "/usr",
                           "--dev", "/dev", "--proc", "/proc",
                           "--", "/usr/bin/true"),
                  timeout = 5, error_on_status = FALSE),
    error = function(e) list(status = 1)
  )
  res$status == 0
}
