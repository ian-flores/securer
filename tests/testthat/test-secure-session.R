test_that("SecureSession can execute simple code", {
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("SecureSession can execute multi-line code", {
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("
    x <- 10
    y <- 20
    x + y
  ")
  expect_equal(result, 30)
})

test_that("SecureSession reports errors in user code", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(session$execute("stop('user error')"), "user error")
})

test_that("SecureSession$close() works", {
  session <- SecureSession$new()
  session$close()
  expect_false(session$is_alive())
})

test_that("execute on closed session errors", {
  session <- SecureSession$new()
  session$close()
  expect_error(session$execute("1"), "not running")
})

test_that("sequential execute() calls work fine", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_equal(session$execute("1 + 1"), 2)
  expect_equal(session$execute("2 + 3"), 5)
  expect_equal(session$execute("10 * 10"), 100)
})

test_that("executing flag resets after error in user code", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(session$execute("stop('boom')"), "boom")
  # Should still work after an error — executing flag must have been reset
  expect_equal(session$execute("42"), 42)
})

test_that("concurrent execute() is rejected", {
  # We can't truly call execute() in parallel from one R session, but we

  # can simulate the guard by manually setting the private field.
  session <- SecureSession$new()
  on.exit(session$close())

  # Reach into the private env to flip the flag
  env <- session$.__enclos_env__$private
  env$executing <- TRUE

  expect_error(
    session$execute("1"),
    "does not support concurrent execute"
  )

  # Reset the flag and confirm normal execution resumes
  env$executing <- FALSE
  expect_equal(session$execute("1 + 1"), 2)
})

test_that("execute() completes within timeout", {
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1", timeout = 5)
  expect_equal(result, 2)
})

test_that("execute() times out on infinite loop", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute("while(TRUE) {}", timeout = 1),
    "timed out after 1 second"
  )
})

test_that("execute() with NULL timeout works normally (no timeout)", {
  session <- SecureSession$new()
  on.exit(session$close())

  # NULL timeout means no limit; a fast expression should complete fine
  result <- session$execute("42", timeout = NULL)
  expect_equal(result, 42)
})

test_that("session is usable after a timeout", {
  session <- SecureSession$new()
  on.exit(session$close())

  # First, cause a timeout

  expect_error(
    session$execute("while(TRUE) {}", timeout = 1),
    "timed out"
  )

  # Session should still be alive and usable
  expect_true(session$is_alive())
  result <- session$execute("100 + 1")
  expect_equal(result, 101)
})
