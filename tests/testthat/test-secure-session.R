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
