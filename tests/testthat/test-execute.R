test_that("execute_r() works for simple code", {
  result <- execute_r("1 + 1", sandbox = FALSE)
  expect_equal(result, 2)
})

test_that("execute_r() works with tools", {
  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  result <- execute_r("add(2, 3)", tools = tools, sandbox = FALSE)
  expect_equal(result, 5)
})

test_that("execute_r() propagates errors", {
  expect_error(execute_r("stop('boom')", sandbox = FALSE), "boom")
})

test_that("execute_r() respects timeout", {
  expect_error(
    execute_r("Sys.sleep(60)", timeout = 1, sandbox = FALSE),
    "timed out|timeout"
  )
})

# Helper: check if sandbox-exec can actually start R with our profile
sandbox_exec_works <- function() {
  if (!file.exists("/usr/bin/sandbox-exec")) return(FALSE)
  tryCatch({
    session <- SecureSession$new(sandbox = TRUE)
    session$close()
    TRUE
  }, error = function(e) FALSE)
}

test_that("execute_r() with sandbox on macOS", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  result <- execute_r("1 + 1", sandbox = TRUE)
  expect_equal(result, 2)
})

test_that("execute_r() with tools and sandbox", {
  skip_on_os(c("windows", "linux"))
  skip_if_not(sandbox_exec_works(), "sandbox-exec cannot start R (likely CI runner path mismatch)")

  tools <- list(
    securer_tool("multiply", "Multiply", function(a, b) a * b,
                 args = list(a = "numeric", b = "numeric"))
  )
  result <- execute_r("multiply(6, 7)", tools = tools, sandbox = TRUE)
  expect_equal(result, 42)
})
