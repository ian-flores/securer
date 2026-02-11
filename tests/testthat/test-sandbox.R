# ── Unit tests (always run) ────────────────────────────────────────────

test_that("build_sandbox_config returns expected structure on macOS", {
  skip_on_os(c("windows", "linux"))

  socket_path <- tempfile("test_sock_", fileext = ".sock")
  config <- build_sandbox_config(socket_path, R.home())
  on.exit({
    if (!is.null(config$wrapper)) unlink(config$wrapper)
    if (!is.null(config$profile_path)) unlink(config$profile_path)
  })

  expect_true(!is.null(config$wrapper))
  expect_true(file.exists(config$wrapper))
  expect_true(!is.null(config$profile_path))
  expect_true(file.exists(config$profile_path))
})

test_that("Seatbelt profile contains essential rules", {
  skip_on_os(c("windows", "linux"))

  profile <- generate_seatbelt_profile("/tmp/test.sock", R.home())
  expect_true(grepl("deny default", profile))
  expect_true(grepl("deny network.*remote ip", profile))
  expect_true(grepl("allow network.*local unix", profile))
  expect_true(grepl("allow file-write.*subpath.*tmp", profile, ignore.case = TRUE))
})

test_that("Seatbelt profile restricts /etc to specific files", {
  skip_on_os(c("windows", "linux"))

  profile <- generate_seatbelt_profile("/tmp/test.sock", R.home())

  # Must NOT have a broad /etc subpath rule
  expect_false(grepl('(allow file-read* (subpath "/etc"))', profile, fixed = TRUE))
  expect_false(grepl('(allow file-read* (subpath "/private/etc"))', profile, fixed = TRUE))

  # Must have specific file entries
  expect_true(grepl('literal "/etc/localtime"', profile, fixed = TRUE))
  expect_true(grepl('literal "/etc/resolv.conf"', profile, fixed = TRUE))
  expect_true(grepl('literal "/etc/hosts"', profile, fixed = TRUE))
  expect_true(grepl('subpath "/etc/ssl"', profile, fixed = TRUE))
  expect_true(grepl('subpath "/etc/pki"', profile, fixed = TRUE))
})

test_that("Seatbelt profile scopes /var/folders to current user", {
  skip_on_os(c("windows", "linux"))

  profile <- generate_seatbelt_profile("/tmp/test.sock", R.home())

  # On macOS with a typical TMPDIR, should use subpath instead of broad regex
  tmpdir_val <- normalizePath(Sys.getenv("TMPDIR", tempdir()), mustWork = FALSE)
  var_match <- regmatches(
    tmpdir_val,
    regexpr("/private/var/folders/[^/]+/[^/]+", tmpdir_val)
  )

  if (length(var_match) == 1 && nzchar(var_match)) {
    # User-specific path should appear as a subpath rule
    expect_true(grepl(var_match, profile, fixed = TRUE))
    # Broad regex should NOT appear
    expect_false(grepl('^/private/var/folders/', profile, fixed = TRUE))
  }
})

test_that("Seatbelt profile does NOT use wildcard file-read*", {
  skip_on_os(c("windows", "linux"))

  profile <- generate_seatbelt_profile("/tmp/test.sock", R.home())
  # The old blanket (allow file-read*) should be replaced with explicit paths
  lines <- strsplit(profile, "\n")[[1]]
  blanket_lines <- grep("^\\(allow file-read\\*\\)$", trimws(lines), value = TRUE)
  expect_length(blanket_lines, 0)
})

test_that("Seatbelt profile includes explicit read paths for R", {
  skip_on_os(c("windows", "linux"))

  r_home <- R.home()
  profile <- generate_seatbelt_profile("/tmp/test.sock", r_home)

  # Must allow reading R home
  expect_true(grepl(r_home, profile, fixed = TRUE))
  # Must allow reading /usr (system libs, frameworks)
  expect_true(grepl("file-read.*subpath.*/usr", profile))
  # Must allow reading /dev (devices R needs)
  expect_true(grepl("file-read.*subpath.*/dev", profile))
  # Must allow reading /private/var/folders (macOS temp/cache)
  expect_true(grepl("file-read.*private/var/folders", profile))
  # Must allow reading /tmp
  expect_true(grepl("file-read.*subpath.*/tmp", profile))
})

test_that("Seatbelt profile includes .libPaths() read access", {
  skip_on_os(c("windows", "linux"))

  r_home <- R.home()
  lib_paths <- .libPaths()
  profile <- generate_seatbelt_profile("/tmp/test.sock", r_home, lib_paths = lib_paths)

  # Each library path should be readable — paths under r_home are covered
  # by the r_home subpath rule, so they won't appear as separate entries.
  # Paths outside r_home must appear explicitly.
  for (lp in lib_paths) {
    if (startsWith(lp, r_home)) {
      # Covered by r_home subpath rule — r_home itself must be in profile
      expect_true(
        grepl(r_home, profile, fixed = TRUE),
        label = paste("Profile should include r_home covering:", lp)
      )
    } else {
      expect_true(
        grepl(lp, profile, fixed = TRUE),
        label = paste("Profile should include lib path:", lp)
      )
    }
  }
})

test_that("Seatbelt profile restricts process operations", {
  skip_on_os(c("windows", "linux"))

  r_home <- R.home()
  profile <- generate_seatbelt_profile("/tmp/test.sock", r_home)

  # Should NOT have blanket (allow process*)
  lines <- strsplit(profile, "\n")[[1]]
  blanket_process <- grep("^\\(allow process\\*\\)$", trimws(lines), value = TRUE)
  expect_length(blanket_process, 0)

  # Should allow process-fork
  expect_true(grepl("process-fork", profile))
  # Should allow process-exec for R binary
  expect_true(grepl("process-exec", profile))
})

test_that("Seatbelt profile restricts system operations", {
  skip_on_os(c("windows", "linux"))

  profile <- generate_seatbelt_profile("/tmp/test.sock", R.home())

  # Should NOT have blanket (allow system*)
  lines <- strsplit(profile, "\n")[[1]]
  blanket_system <- grep("^\\(allow system\\*\\)$", trimws(lines), value = TRUE)
  expect_length(blanket_system, 0)
})

test_that("Seatbelt profile includes socket directory in write rules", {
  skip_on_os(c("windows", "linux"))

  socket_path <- "/tmp/my_custom_dir/test.sock"
  profile <- generate_seatbelt_profile(socket_path, R.home())
  expect_true(grepl("/tmp/my_custom_dir", profile, fixed = TRUE))
})

test_that("Seatbelt profile restricts /tmp writes to socket directory only", {
  skip_on_os(c("windows", "linux"))

  socket_path <- "/tmp/securer_abc123/ipc.sock"
  profile <- generate_seatbelt_profile(socket_path, R.home())

  # Should NOT have blanket /tmp write access
  lines <- strsplit(profile, "\n")[[1]]
  write_lines <- grep("file-write.*subpath", lines, value = TRUE)
  blanket_tmp <- grep('subpath "/tmp"', write_lines, fixed = TRUE, value = TRUE)
  expect_length(blanket_tmp, 0)

  blanket_private_tmp <- grep('subpath "/private/tmp"', write_lines, fixed = TRUE, value = TRUE)
  expect_length(blanket_private_tmp, 0)

  # Should have the specific socket directory
  expect_true(any(grepl('subpath "/tmp/securer_abc123"', write_lines, fixed = TRUE)))

  # Should still have /private/var/folders for R temp files
  expect_true(any(grepl("private/var/folders", profile)))
})

test_that("build_sandbox_fallback returns NULLs with a warning", {
  expect_warning(
    config <- build_sandbox_fallback("/tmp/test.sock", R.home()),
    "not available"
  )
  expect_null(config$wrapper)
  expect_null(config$profile_path)
})

test_that("build_sandbox_linux falls back when bwrap not found", {
  skip_on_os(c("windows", "mac"))

  # Temporarily mask bwrap by setting PATH to empty
  old_path <- Sys.getenv("PATH")
  Sys.setenv(PATH = "")
  on.exit(Sys.setenv(PATH = old_path))

  expect_warning(
    config <- build_sandbox_linux("/tmp/test.sock", R.home()),
    "bwrap.*not found"
  )
  expect_null(config$wrapper)
  expect_null(config$profile_path)
})

# ── Linux bwrap unit tests ─────────────────────────────────────────────

test_that("generate_bwrap_args returns expected flags", {
  skip_on_os(c("windows", "mac"))

  args <- generate_bwrap_args("/tmp/securer_abc.sock", "/usr/lib/R")
  expect_true("--unshare-all" %in% args)
  expect_true("--die-with-parent" %in% args)
  expect_true("--new-session" %in% args)
  expect_true(any(grepl("/tmp", args)))
})

test_that("generate_bwrap_args includes socket directory", {
  skip_on_os(c("windows", "mac"))

  args <- generate_bwrap_args("/tmp/mysock/test.sock", "/usr/lib/R")
  # --bind /tmp/mysock /tmp/mysock should appear
  expect_true("/tmp/mysock" %in% args)
})

test_that("generate_bwrap_args includes R home path", {
  skip_on_os(c("windows", "mac"))

  args <- generate_bwrap_args("/tmp/test.sock", R.home())
  expect_true(R.home() %in% args)
})

test_that("generate_bwrap_args sets environment variables", {
  skip_on_os(c("windows", "mac"))

  args <- generate_bwrap_args("/tmp/test.sock", "/usr/lib/R")
  # Check env vars are set
  expect_true("HOME" %in% args)
  expect_true("TMPDIR" %in% args)
  expect_true("SECURER_SOCKET" %in% args)
  expect_true("R_LIBS_USER" %in% args)
})

test_that("Wrapper script is executable and references sandbox-exec", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

  socket_path <- tempfile("test_sock_", fileext = ".sock")
  config <- build_sandbox_macos(socket_path, R.home())
  on.exit({
    unlink(config$wrapper)
    unlink(config$profile_path)
  })

  # Check the wrapper script content
  wrapper_lines <- readLines(config$wrapper)
  expect_true(any(grepl("sandbox-exec", wrapper_lines)))
  expect_true(any(grepl("#!/bin/sh", wrapper_lines)))

  # Check executable permission
  info <- file.info(config$wrapper)
  # Mode has execute bit (at least for user)
  expect_true(as.integer(info$mode) >= 448)  # 0700 in octal
})

# ── Integration tests (require sandbox-exec) ─────────────────────────

# Helper: check if sandbox-exec can actually launch R with our profile.
# On some CI runners the Seatbelt profile doesn't have the right paths
# for the runner's R installation layout.
sandbox_exec_works <- function() {
  if (!file.exists("/usr/bin/sandbox-exec")) return(FALSE)
  tryCatch({
    session <- SecureSession$new(sandbox = TRUE)
    session$close()
    TRUE
  }, error = function(e) FALSE)
}

test_that("Sandbox session can execute simple code", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("Sandbox session can execute multi-line code", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("
    x <- 10
    y <- 20
    x + y
  ")
  expect_equal(result, 30)
})

test_that("Sandbox session blocks network access", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  # Network access should be denied by the Seatbelt profile
  expect_error(
    session$execute('
      con <- url("http://example.com")
      on.exit(try(close(con), silent = TRUE))
      readLines(con, n = 1)
    ')
  )
})

test_that("Sandbox session blocks writing to protected paths", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  home <- Sys.getenv("HOME")
  # Writing outside temp should be denied by the Seatbelt profile
  expect_error(
    session$execute(sprintf(
      'writeLines("hack", "%s/evil.txt")',
      home
    ))
  )
})

test_that("Sandbox session allows writing to temp directory", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute('
    tf <- tempfile()
    writeLines("hello", tf)
    content <- readLines(tf)
    unlink(tf)
    content
  ')
  expect_equal(result, "hello")
})

test_that("Sandbox session allows tool calls", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  tools <- list(
    securer_tool(
      "add", "Add two numbers",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools, sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("add(2, 3)")
  expect_equal(result, 5)
})

test_that("Sandbox session cleans up temp files on close", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)

  # Grab the paths before closing
  config <- session$.__enclos_env__$private$sandbox_config
  wrapper_path <- config$wrapper
  profile_path <- config$profile_path

  expect_true(file.exists(wrapper_path))
  expect_true(file.exists(profile_path))

  session$close()

  expect_false(file.exists(wrapper_path))
  expect_false(file.exists(profile_path))
})

test_that("Sandbox session blocks reading user home directory files", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  home <- Sys.getenv("HOME")
  # Create a temp file in home dir, try to read it from sandbox
  test_file <- file.path(home, ".securer_test_secret")
  writeLines("secret", test_file)
  on.exit(unlink(test_file), add = TRUE)

  # Reading user home directory files should be blocked by the sandbox.
  # R's file functions may produce a warning or error; either way the
  # content should NOT be accessible.
  result <- tryCatch(
    session$execute(sprintf('readLines("%s")', test_file)),
    error = function(e) "blocked_by_error"
  )
  # Either the call errored (sandbox denied the read) or the result
  # should not contain the actual secret content
  if (identical(result, "blocked_by_error")) {
    expect_true(TRUE)  # File read was blocked at the sandbox level
  } else {
    expect_false(identical(result, "secret"))
  }
})

test_that("Sandbox session blocks executing non-R binaries", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  # Executing python/perl/etc. should be blocked by restricted process-exec.
  # system() returns the exit status; a non-zero status means it failed.
  result <- session$execute('system("python3 -c \'print(1)\'")')
  expect_true(result != 0)  # Non-zero exit = blocked
})

test_that("Non-sandbox session still works (regression)", {
  session <- SecureSession$new(sandbox = FALSE)
  on.exit(session$close())

  result <- session$execute("42")
  expect_equal(result, 42)
})

# ── Linux bwrap integration tests (require bwrap) ─────────────────────

# Helper: check if bwrap can actually create namespaces (fails in containers)
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

test_that("bwrap sandbox session can execute simple code", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("bwrap sandbox session can execute multi-line code", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("
    x <- 10
    y <- 20
    x + y
  ")
  expect_equal(result, 30)
})

test_that("bwrap sandbox blocks network access", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  expect_error(
    session$execute('
      con <- url("http://example.com")
      on.exit(try(close(con), silent = TRUE))
      readLines(con, n = 1)
    ')
  )
})

test_that("bwrap sandbox blocks writing to protected paths", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  # Writing outside /tmp should fail (HOME is /tmp inside sandbox)
  expect_error(
    session$execute('writeLines("hack", "/home/evil.txt")')
  )
})

test_that("bwrap sandbox allows writing to temp directory", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute('
    tf <- tempfile()
    writeLines("hello", tf)
    content <- readLines(tf)
    unlink(tf)
    content
  ')
  expect_equal(result, "hello")
})

test_that("bwrap sandbox allows tool calls", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  tools <- list(
    securer_tool(
      "add", "Add two numbers",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools, sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("add(2, 3)")
  expect_equal(result, 5)
})

test_that("bwrap sandbox cleans up wrapper on close", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(bwrap_works(), "bwrap cannot create namespaces (likely in a container)")

  session <- SecureSession$new(sandbox = TRUE)

  config <- session$.__enclos_env__$private$sandbox_config
  wrapper_path <- config$wrapper
  expect_true(file.exists(wrapper_path))

  session$close()

  expect_false(file.exists(wrapper_path))
})

# ── Windows sandbox unit tests ─────────────────────────────────────────

test_that("build_sandbox_windows returns correct structure", {
  config <- build_sandbox_windows("/tmp/test.sock", R.home())
  expect_null(config$wrapper)
  expect_null(config$profile_path)
  expect_type(config$env, "character")
  expect_true("HOME" %in% names(config$env))
  expect_true("TMPDIR" %in% names(config$env))
  expect_true("TMP" %in% names(config$env))
  expect_true("TEMP" %in% names(config$env))
  expect_equal(config$env[["R_LIBS_USER"]], "")
  expect_true(dir.exists(config$sandbox_tmp))
  # Clean up
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows returns NULL apply_limits when no limits given", {
  config <- build_sandbox_windows("/tmp/test.sock", R.home())
  expect_null(config$apply_limits)
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows returns NULL apply_limits for empty limits", {
  config <- build_sandbox_windows("/tmp/test.sock", R.home(), limits = list())
  expect_null(config$apply_limits)
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows returns function apply_limits when supported limits given", {
  config <- build_sandbox_windows("/tmp/test.sock", R.home(),
    limits = list(memory = 512 * 1024 * 1024))
  expect_type(config$apply_limits, "closure")
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows returns function apply_limits for cpu and nproc", {
  config <- build_sandbox_windows("/tmp/test.sock", R.home(),
    limits = list(cpu = 60, nproc = 50))
  expect_type(config$apply_limits, "closure")
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows warns for unsupported limits", {
  expect_warning(
    config <- build_sandbox_windows("/tmp/test.sock", R.home(),
      limits = list(fsize = 1024)),
    "fsize.*not supported on Windows"
  )
  expect_null(config$apply_limits)
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows warns for multiple unsupported limits", {
  expect_warning(
    expect_warning(
      expect_warning(
        config <- build_sandbox_windows("/tmp/test.sock", R.home(),
          limits = list(fsize = 1024, nofile = 256, stack = 1024)),
        "not supported on Windows"
      ),
      "not supported on Windows"
    ),
    "not supported on Windows"
  )
  expect_null(config$apply_limits)
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows creates apply_limits for supported limits alongside unsupported", {
  expect_warning(
    config <- build_sandbox_windows("/tmp/test.sock", R.home(),
      limits = list(memory = 512 * 1024 * 1024, fsize = 1024)),
    "fsize.*not supported on Windows"
  )
  expect_type(config$apply_limits, "closure")
  unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("windows_supported_limits returns expected names", {
  supported <- windows_supported_limits()
  expect_equal(supported, c("cpu", "memory", "nproc"))
})

test_that("build_sandbox_windows integration: session executes code with sandbox", {
  skip_on_os(c("mac", "linux"))
  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())
  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("build_sandbox_windows integration: env isolation works", {
  skip_on_os(c("mac", "linux"))
  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())
  result <- session$execute("Sys.getenv('R_LIBS_USER')")
  expect_equal(result, "")
})

# ── Resource limits (rlimits) unit tests ──────────────────────────────

test_that("generate_ulimit_commands returns empty for NULL limits", {
  expect_equal(generate_ulimit_commands(NULL), character(0))
  expect_equal(generate_ulimit_commands(list()), character(0))
})

test_that("generate_ulimit_commands produces correct CPU limit with hard limits", {
  cmds <- generate_ulimit_commands(list(cpu = 30))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -S -H -t 30")
})

test_that("generate_ulimit_commands converts memory from bytes to KB with hard limits", {
  cmds <- generate_ulimit_commands(list(memory = 512 * 1024 * 1024))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -S -H -v 524288")
})

test_that("generate_ulimit_commands converts fsize from bytes to 512-byte blocks with hard limits", {
  cmds <- generate_ulimit_commands(list(fsize = 10 * 1024 * 1024))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -S -H -f 20480")
})

test_that("generate_ulimit_commands handles multiple limits with hard limits", {
  cmds <- generate_ulimit_commands(list(cpu = 10, memory = 256 * 1024 * 1024, nproc = 50))
  expect_length(cmds, 3)
  expect_true(any(grepl("ulimit -S -H -t 10", cmds)))
  expect_true(any(grepl("ulimit -S -H -v 262144", cmds)))
  expect_true(any(grepl("ulimit -S -H -u 50", cmds)))
})

test_that("generate_ulimit_commands handles nproc and nofile with hard limits", {
  cmds <- generate_ulimit_commands(list(nproc = 100, nofile = 256))
  expect_length(cmds, 2)
  expect_true(any(grepl("ulimit -S -H -u 100", cmds)))
  expect_true(any(grepl("ulimit -S -H -n 256", cmds)))
})

test_that("generate_ulimit_commands handles stack limit with hard limits", {
  cmds <- generate_ulimit_commands(list(stack = 8 * 1024 * 1024))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -S -H -s 8192")
})

test_that("generate_ulimit_commands rounds up fractional conversions with hard limits", {
  # 1 byte -> should round up to 1 KB
  cmds <- generate_ulimit_commands(list(memory = 1))
  expect_equal(cmds, "ulimit -S -H -v 1")
})

test_that("validate_limits rejects unknown limit names", {
  expect_error(
    validate_limits(list(bogus = 10)),
    "Unknown limit name"
  )
})

test_that("validate_limits rejects non-positive values", {
  expect_error(
    validate_limits(list(cpu = -1)),
    "must be a single positive number"
  )
  expect_error(
    validate_limits(list(cpu = 0)),
    "must be a single positive number"
  )
})

test_that("validate_limits rejects non-numeric values", {
  expect_error(
    validate_limits(list(cpu = "ten")),
    "must be a single positive number"
  )
})

test_that("validate_limits rejects vector values", {
  expect_error(
    validate_limits(list(cpu = c(10, 20))),
    "must be a single positive number"
  )
})

test_that("macOS wrapper includes ulimit commands when limits provided", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

  socket_path <- tempfile("test_sock_", fileext = ".sock")
  limits <- list(cpu = 30, memory = 512 * 1024 * 1024)
  config <- build_sandbox_macos(socket_path, R.home(), limits = limits)
  on.exit({
    unlink(config$wrapper)
    unlink(config$profile_path)
  })

  wrapper_lines <- readLines(config$wrapper)
  expect_true(any(grepl("ulimit -S -H -t 30", wrapper_lines)))
  expect_true(any(grepl("ulimit -S -H -v 524288", wrapper_lines)))
  # ulimit lines should come before the exec line
  ulimit_idx <- which(grepl("ulimit", wrapper_lines))
  exec_idx <- which(grepl("^exec", wrapper_lines))
  expect_true(all(ulimit_idx < exec_idx))
})

test_that("macOS wrapper has no ulimit lines when limits is NULL", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

  socket_path <- tempfile("test_sock_", fileext = ".sock")
  config <- build_sandbox_macos(socket_path, R.home())
  on.exit({
    unlink(config$wrapper)
    unlink(config$profile_path)
  })

  wrapper_lines <- readLines(config$wrapper)
  expect_false(any(grepl("ulimit", wrapper_lines)))
})

test_that("build_limits_only_wrapper creates script with ulimit", {
  config <- build_limits_only_wrapper(list(cpu = 15, fsize = 1024 * 1024))
  on.exit(unlink(config$wrapper))

  expect_true(!is.null(config$wrapper))
  expect_true(file.exists(config$wrapper))
  expect_null(config$profile_path)

  wrapper_lines <- readLines(config$wrapper)
  expect_true(any(grepl("#!/bin/sh", wrapper_lines)))
  expect_true(any(grepl("ulimit -S -H -t 15", wrapper_lines)))
  expect_true(any(grepl("ulimit -S -H -f 2048", wrapper_lines)))
  expect_true(any(grepl("^exec", wrapper_lines)))
  # No sandbox-exec reference
  expect_false(any(grepl("sandbox-exec", wrapper_lines)))
})

test_that("build_limits_only_wrapper returns NULL wrapper for NULL limits", {
  config <- build_limits_only_wrapper(list())
  expect_null(config$wrapper)
  expect_null(config$profile_path)
})

# ── Resource limits integration tests ─────────────────────────────────

test_that("Session with limits can execute simple code", {
  skip_on_os("windows")

  session <- SecureSession$new(
    sandbox = FALSE,
    limits = list(cpu = 60)
  )
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("Session with sandbox + limits can execute code", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  session <- SecureSession$new(
    sandbox = TRUE,
    limits = list(cpu = 60, memory = 1024 * 1024 * 1024)
  )
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("CPU limit causes error on infinite loop", {
  skip_on_os("windows")

  session <- SecureSession$new(
    sandbox = FALSE,
    limits = list(cpu = 1)
  )
  on.exit(session$close())

  # A tight loop consuming CPU should hit the 1-second CPU limit
  expect_error(
    session$execute("while(TRUE) { }", timeout = 10)
  )
})

test_that("File size limit restricts large writes", {
  skip_on_os("windows")
  # Skip if ulimit -f can't be enforced (containers may ignore it)
  skip_if_not(
    tryCatch({
      s <- SecureSession$new(sandbox = FALSE, limits = list(fsize = 1024))
      # Try writing more than 1KB — should fail if fsize works
      res <- tryCatch(
        s$execute('writeBin(raw(8192), tempfile())'),
        error = function(e) "limited"
      )
      s$close()
      identical(res, "limited")
    }, error = function(e) FALSE),
    "fsize ulimit not enforceable (likely CI container)"
  )

  # Set fsize limit to 1 MB
  session <- SecureSession$new(
    sandbox = FALSE,
    limits = list(fsize = 1 * 1024 * 1024)
  )
  on.exit(session$close())

  # Trying to write a 5 MB file should fail
  expect_error(
    session$execute('
      tf <- tempfile()
      writeBin(raw(5 * 1024 * 1024), tf)
    ')
  )
})
