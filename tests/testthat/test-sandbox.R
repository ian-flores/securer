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
