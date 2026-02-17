test_that("execute_r() works for simple code", {
  skip_if_no_session()
  result <- execute_r("1 + 1", sandbox = FALSE)
  expect_equal(result, 2)
})

test_that("execute_r() works with tools", {
  skip_if_no_session()
  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  result <- execute_r("add(2, 3)", tools = tools, sandbox = FALSE)
  expect_equal(result, 5)
})

test_that("execute_r() propagates errors", {
  skip_if_no_session()
  expect_error(execute_r("stop('boom')", sandbox = FALSE), "boom")
})

test_that("execute_r() respects timeout", {
  skip_if_no_session()
  expect_error(
    execute_r("Sys.sleep(60)", timeout = 1, sandbox = FALSE),
    "timed out|timeout"
  )
})

test_that("execute_r() with sandbox on macOS", {
  skip_if_no_session()
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  result <- execute_r("1 + 1", sandbox = TRUE)
  expect_equal(result, 2)
})

test_that("execute_r() with tools and sandbox", {
  skip_if_no_session()
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  tools <- list(
    securer_tool("multiply", "Multiply", function(a, b) a * b,
                 args = list(a = "numeric", b = "numeric"))
  )
  result <- execute_r("multiply(6, 7)", tools = tools, sandbox = TRUE)
  expect_equal(result, 42)
})

# --- with_secure_session() tests ---

test_that("with_secure_session() runs code and returns result", {
  skip_if_no_session()
  result <- with_secure_session(function(session) {
    session$execute("1 + 1")
  }, sandbox = FALSE)
  expect_equal(result, 2)
})

test_that("with_secure_session() cleans up session on normal exit", {
  skip_if_no_session()
  session_ref <- NULL
  with_secure_session(function(session) {
    session_ref <<- session
    session$execute("1")
  }, sandbox = FALSE)
  # Session should be closed after the function returns
  expect_false(session_ref$is_alive())
})

test_that("with_secure_session() cleans up session on error", {
  skip_if_no_session()
  session_ref <- NULL
  tryCatch(
    with_secure_session(function(session) {
      session_ref <<- session
      stop("boom")
    }, sandbox = FALSE),
    error = function(e) NULL
  )
  # Session should be closed even after an error
  expect_false(session_ref$is_alive())
})

test_that("with_secure_session() preserves state across calls", {
  skip_if_no_session()
  result <- with_secure_session(function(session) {
    session$execute("x <- 10")
    session$execute("x * 2")
  }, sandbox = FALSE)
  expect_equal(result, 20)
})

test_that("with_secure_session() works with tools", {
  skip_if_no_session()
  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  result <- with_secure_session(function(session) {
    session$execute("add(3, 4)")
  }, tools = tools, sandbox = FALSE)
  expect_equal(result, 7)
})
