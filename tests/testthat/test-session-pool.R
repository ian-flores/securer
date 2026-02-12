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

# --- print/format method tests ---

test_that("pool format() shows size and idle/busy counts", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  out <- format(pool)
  expect_match(out, "SecureSessionPool")
  expect_match(out, "size=2")
  expect_match(out, "idle=2")
  expect_match(out, "busy=0")
})

test_that("pool format() shows closed state", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  pool$close()

  out <- format(pool)
  expect_match(out, "closed")
})

test_that("pool format() reflects busy sessions", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  priv <- pool$.__enclos_env__$private
  priv$busy[[1]] <- TRUE

  out <- format(pool)
  expect_match(out, "idle=1")
  expect_match(out, "busy=1")

  priv$busy[[1]] <- FALSE
})

test_that("pool print() outputs format string", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  out <- capture.output(print(pool))
  expect_match(out, "SecureSessionPool")
})

# --- acquire_timeout tests (R8) ---

test_that("acquire_timeout retries instead of failing immediately", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  on.exit(pool$close())

  # Simulate the single session being busy
  priv <- pool$.__enclos_env__$private
  priv$busy[[1]] <- TRUE

  # With acquire_timeout = 0.3, it should retry for ~0.3 seconds before failing
  start <- Sys.time()
  expect_error(
    pool$execute("1 + 1", acquire_timeout = 0.3),
    "All sessions are busy"
  )
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  # Should have waited at least ~0.2 seconds (some tolerance for timing)
  expect_true(elapsed >= 0.2)

  # Reset busy flag for cleanup
  priv$busy[[1]] <- FALSE
})

test_that("acquire_timeout = NULL fails immediately (default behavior)", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  on.exit(pool$close())

  priv <- pool$.__enclos_env__$private
  priv$busy[[1]] <- TRUE

  start <- Sys.time()
  expect_error(pool$execute("1"), "All sessions are busy")
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  # Should fail essentially immediately (< 0.1s)
  expect_true(elapsed < 0.15)

  priv$busy[[1]] <- FALSE
})

test_that("acquire_timeout succeeds when session becomes available", {
  pool <- SecureSessionPool$new(size = 1, sandbox = FALSE)
  on.exit(pool$close())

  priv <- pool$.__enclos_env__$private
  priv$busy[[1]] <- TRUE

  # Release the session after a short delay using a later callback
  # Since R is single-threaded, we simulate by releasing before the call
  priv$busy[[1]] <- FALSE

  result <- pool$execute("42", acquire_timeout = 1)
  expect_equal(result, 42)
})

# --- status() method tests (R8) ---

test_that("status() returns correct counts for healthy pool", {
  pool <- SecureSessionPool$new(size = 3, sandbox = FALSE)
  on.exit(pool$close())

  st <- pool$status()
  expect_equal(st$total, 3L)
  expect_equal(st$busy, 0L)
  expect_equal(st$idle, 3L)
  expect_equal(st$dead, 0L)
})

test_that("status() reflects busy sessions", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  priv <- pool$.__enclos_env__$private
  priv$busy[[1]] <- TRUE

  st <- pool$status()
  expect_equal(st$total, 2L)
  expect_equal(st$busy, 1L)
  expect_equal(st$idle, 1L)
  expect_equal(st$dead, 0L)

  priv$busy[[1]] <- FALSE
})

test_that("status() detects dead sessions", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  on.exit(pool$close())

  # Kill one session to make it dead
  priv <- pool$.__enclos_env__$private
  priv$sessions[[1]]$close()

  st <- pool$status()
  expect_equal(st$total, 2L)
  expect_equal(st$busy, 0L)
  expect_equal(st$idle, 1L)
  expect_equal(st$dead, 1L)
})

test_that("status() returns zeros for closed pool", {
  pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
  pool$close()

  st <- pool$status()
  expect_equal(st$total, 0L)
  expect_equal(st$busy, 0L)
  expect_equal(st$idle, 0L)
  expect_equal(st$dead, 0L)
})
