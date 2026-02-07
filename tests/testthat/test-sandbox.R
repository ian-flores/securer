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
  expect_true(grepl("allow file-read\\*", profile))
  expect_true(grepl("allow network.*local unix", profile))
  expect_true(grepl("allow file-write.*subpath.*tmp", profile, ignore.case = TRUE))
})

test_that("Seatbelt profile includes socket directory in write rules", {
  skip_on_os(c("windows", "linux"))

  socket_path <- "/tmp/my_custom_dir/test.sock"
  profile <- generate_seatbelt_profile(socket_path, R.home())
  expect_true(grepl("/tmp/my_custom_dir", profile, fixed = TRUE))
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

test_that("Sandbox session can execute simple code", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("Sandbox session can execute multi-line code", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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

test_that("Non-sandbox session still works (regression)", {
  session <- SecureSession$new(sandbox = FALSE)
  on.exit(session$close())

  result <- session$execute("42")
  expect_equal(result, 42)
})

# ── Linux bwrap integration tests (require bwrap) ─────────────────────

test_that("bwrap sandbox session can execute simple code", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("bwrap sandbox session can execute multi-line code", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

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
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

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
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

  session <- SecureSession$new(sandbox = TRUE)
  on.exit(session$close())

  # Writing outside /tmp should fail (HOME is /tmp inside sandbox)
  expect_error(
    session$execute('writeLines("hack", "/home/evil.txt")')
  )
})

test_that("bwrap sandbox allows writing to temp directory", {
  skip_on_os(c("windows", "mac"))
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

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
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

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
  skip_if_not(nzchar(Sys.which("bwrap")), "bwrap not available")

  session <- SecureSession$new(sandbox = TRUE)

  config <- session$.__enclos_env__$private$sandbox_config
  wrapper_path <- config$wrapper
  expect_true(file.exists(wrapper_path))

  session$close()

  expect_false(file.exists(wrapper_path))
})

# ── Windows sandbox unit tests ─────────────────────────────────────────

test_that("build_sandbox_windows returns config with env and warning", {
  # This test can run on any platform since it tests the function directly
  expect_warning(
    config <- build_sandbox_windows("/tmp/test.sock", R.home()),
    "environment isolation only"
  )

  # No wrapper or profile on Windows

  expect_null(config$wrapper)
  expect_null(config$profile_path)

  # Must have env field with restrictive variables
  expect_true(!is.null(config$env))
  expect_true(is.character(config$env))
  expect_true("R_LIBS_USER" %in% names(config$env))
  expect_true("HOME" %in% names(config$env))
  expect_true("TMPDIR" %in% names(config$env))
  expect_true("R_ENVIRON_USER" %in% names(config$env))
  expect_true("R_PROFILE_USER" %in% names(config$env))
  expect_true("R_USER" %in% names(config$env))

  # R_LIBS_USER should be empty to prevent user packages
  expect_equal(unname(config$env["R_LIBS_USER"]), "")

  # Cleanup sandbox temp dir
  if (!is.null(config$sandbox_tmp)) unlink(config$sandbox_tmp, recursive = TRUE)
})

test_that("build_sandbox_windows creates a clean temp directory", {
  expect_warning(
    config <- build_sandbox_windows("/tmp/test.sock", R.home()),
    "environment isolation only"
  )
  on.exit({
    if (!is.null(config$sandbox_tmp)) unlink(config$sandbox_tmp, recursive = TRUE)
  })

  expect_true(!is.null(config$sandbox_tmp))
  expect_true(dir.exists(config$sandbox_tmp))

  # HOME, TMPDIR, TMP, TEMP should all point to the sandbox temp dir
  expect_equal(unname(config$env["HOME"]), config$sandbox_tmp)
  expect_equal(unname(config$env["TMPDIR"]), config$sandbox_tmp)
  expect_equal(unname(config$env["TMP"]), config$sandbox_tmp)
  expect_equal(unname(config$env["TEMP"]), config$sandbox_tmp)
  expect_equal(unname(config$env["R_USER"]), config$sandbox_tmp)
})

test_that("build_sandbox_windows clears startup scripts", {
  expect_warning(
    config <- build_sandbox_windows("/tmp/test.sock", R.home()),
    "environment isolation only"
  )
  on.exit({
    if (!is.null(config$sandbox_tmp)) unlink(config$sandbox_tmp, recursive = TRUE)
  })

  # R_ENVIRON_USER and R_PROFILE_USER should be empty to prevent
  # user startup code from running
  expect_equal(unname(config$env["R_ENVIRON_USER"]), "")
  expect_equal(unname(config$env["R_PROFILE_USER"]), "")
})

# ── Resource limits (rlimits) unit tests ──────────────────────────────

test_that("generate_ulimit_commands returns empty for NULL limits", {
  expect_equal(generate_ulimit_commands(NULL), character(0))
  expect_equal(generate_ulimit_commands(list()), character(0))
})

test_that("generate_ulimit_commands produces correct CPU limit", {
  cmds <- generate_ulimit_commands(list(cpu = 30))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -t 30")
})

test_that("generate_ulimit_commands converts memory from bytes to KB", {
  cmds <- generate_ulimit_commands(list(memory = 512 * 1024 * 1024))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -v 524288")
})

test_that("generate_ulimit_commands converts fsize from bytes to 512-byte blocks", {
  cmds <- generate_ulimit_commands(list(fsize = 10 * 1024 * 1024))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -f 20480")
})

test_that("generate_ulimit_commands handles multiple limits", {
  cmds <- generate_ulimit_commands(list(cpu = 10, memory = 256 * 1024 * 1024, nproc = 50))
  expect_length(cmds, 3)
  expect_true(any(grepl("ulimit -t 10", cmds)))
  expect_true(any(grepl("ulimit -v 262144", cmds)))
  expect_true(any(grepl("ulimit -u 50", cmds)))
})

test_that("generate_ulimit_commands handles nproc and nofile", {
  cmds <- generate_ulimit_commands(list(nproc = 100, nofile = 256))
  expect_length(cmds, 2)
  expect_true(any(grepl("ulimit -u 100", cmds)))
  expect_true(any(grepl("ulimit -n 256", cmds)))
})

test_that("generate_ulimit_commands handles stack limit", {
  cmds <- generate_ulimit_commands(list(stack = 8 * 1024 * 1024))
  expect_length(cmds, 1)
  expect_equal(cmds, "ulimit -s 8192")
})

test_that("generate_ulimit_commands rounds up fractional conversions", {
  # 1 byte -> should round up to 1 KB
  cmds <- generate_ulimit_commands(list(memory = 1))
  expect_equal(cmds, "ulimit -v 1")
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
  expect_true(any(grepl("ulimit -t 30", wrapper_lines)))
  expect_true(any(grepl("ulimit -v 524288", wrapper_lines)))
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
  expect_true(any(grepl("ulimit -t 15", wrapper_lines)))
  expect_true(any(grepl("ulimit -f 2048", wrapper_lines)))
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
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

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
