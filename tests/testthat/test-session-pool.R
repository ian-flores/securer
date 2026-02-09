test_that("SecureSessionPool creates N sessions", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  # All sessions should be alive
  expect_equal(pool$size(), 2)
  expect_equal(pool$available(), 2)
})

test_that("SecureSessionPool$execute() runs code and returns result", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  result <- pool$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("sequential executions reuse sessions from pool", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  r1 <- pool$execute("10 + 1")
  r2 <- pool$execute("20 + 2")
  r3 <- pool$execute("30 + 3")

  expect_equal(r1, 11)
  expect_equal(r2, 22)
  expect_equal(r3, 33)

  # All sessions should be available again after sequential use

  expect_equal(pool$available(), 2)
})

test_that("pool with tools works", {
  tools <- list(
    securer_tool("add", "Add two numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )

  pool <- SecureSessionPool$new(size = 2, tools = tools, sandbox = FALSE)
  on.exit(pool$close())

  result <- pool$execute("add(3, 4)")
  expect_equal(result, 7)
})

test_that("close() shuts down all sessions", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  pool$close()

  expect_equal(pool$available(), 0)
  expect_equal(pool$size(), 0)
})

test_that("execute on closed pool errors", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  pool$close()

  expect_error(pool$execute("1"), "Pool is closed")
})

test_that("error in execution doesn't break the pool", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  # Cause an error
  expect_error(pool$execute("stop('boom')"), "boom")

  # Pool should still be usable
  result <- pool$execute("42")
  expect_equal(result, 42)

  # All sessions should be available
  expect_equal(pool$available(), 2)
})

test_that("pool respects timeout", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  on.exit(pool$close())

  expect_error(
    pool$execute("while(TRUE) {}", timeout = 1),
    "timed out"
  )

  # Pool should still be usable after timeout
  result <- pool$execute("99")
  expect_equal(result, 99)
})

test_that("pool size must be positive", {
  expect_error(
    SecureSessionPool$new(size = 0, sandbox = FALSE),
    "at least 1"
  )
})

test_that("default pool size is 4", {
  pool <- SecureSessionPool$new(sandbox = FALSE)
  on.exit(pool$close())

  expect_equal(pool$size(), 4)
})

test_that("dead session is auto-restarted on acquire", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  # Kill the first session so it is no longer alive
  priv <- pool$.__enclos_env__$private
  priv$sessions[[1]]$close()
  expect_false(priv$sessions[[1]]$is_alive())

  # execute() should transparently restart the dead session and succeed

  result <- pool$execute("1 + 1")
  expect_equal(result, 2)

  # The restarted session should now be alive
  expect_true(priv$sessions[[1]]$is_alive())

  # Pool should still report both sessions available after execution
  expect_equal(pool$available(), 2)
})

test_that("execute errors when all sessions are busy", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  on.exit(pool$close())

  # Simulate the single session being busy by setting the flag directly
  priv <- pool$.__enclos_env__$private
  priv$busy[[1]] <- TRUE

  expect_error(pool$execute("1 + 1"), "All sessions are busy")

  # Reset the flag so cleanup can proceed normally
  priv$busy[[1]] <- FALSE
})
