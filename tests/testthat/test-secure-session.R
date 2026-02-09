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

# --- Streaming output capture tests ---

test_that("execute() captures cat() output", {
  session <- SecureSession$new()
  on.exit(session$close())

  # cat() + explicit return value so we can check the output attribute
  result <- session$execute('cat("hello world"); TRUE')
  expect_true(result)
  expect_equal(attr(result, "output"), "hello world")
})

test_that("execute() captures print() output", {
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("print(1:3)")
  output <- attr(result, "output")
  expect_true(length(output) > 0)
  expect_true(any(grepl("1 2 3", output)))
})

test_that("output_handler receives lines as they arrive", {
  session <- SecureSession$new()
  on.exit(session$close())

  collected <- character()
  handler <- function(line) {
    collected <<- c(collected, line)
  }

  result <- session$execute('cat("line1\\nline2\\n"); TRUE', output_handler = handler)
  expect_true(length(collected) > 0)
  expect_true("line1" %in% collected)
  expect_true("line2" %in% collected)
})

test_that("output and return value are separate", {
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute('cat("msg\\n"); 42')
  expect_equal(result, 42, ignore_attr = TRUE)
  output <- attr(result, "output")
  expect_true(any(grepl("msg", output)))
})

# --- Rate limiting tests (Finding 14) ---

test_that("max_tool_calls limits tool invocations", {
  tools <- list(
    securer_tool(
      "counter", "Count calls",
      function() 1,
      args = list()
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Allow exactly 2 tool calls; code calls 3 times
  expect_error(
    session$execute("counter(); counter(); counter()", max_tool_calls = 2),
    "Maximum tool calls \\(2\\) exceeded"
  )
})

test_that("max_tool_calls NULL allows unlimited tool calls", {
  tools <- list(
    securer_tool(
      "inc", "Increment",
      function(x) x + 1,
      args = list(x = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute("
    a <- inc(1)
    b <- inc(a)
    c <- inc(b)
    c
  ", max_tool_calls = NULL)
  expect_equal(result, 4)
})

test_that("max_tool_calls allows exactly the limit", {
  tools <- list(
    securer_tool(
      "inc", "Increment",
      function(x) x + 1,
      args = list(x = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Allow exactly 2 tool calls, and code makes exactly 2

  result <- session$execute("
    a <- inc(1)
    b <- inc(a)
    b
  ", max_tool_calls = 2)
  expect_equal(result, 3)
})

# --- Parent-side argument validation tests (Finding 5) ---

test_that("unexpected tool arguments are rejected by parent", {
  tools <- list(
    securer_tool(
      "add", "Add numbers",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Call with an unexpected argument name via .securer_call_tool()
  expect_error(
    session$execute('.securer_call_tool("add", a = 1, b = 2, evil = 999)'),
    "Unexpected arguments.*'evil'"
  )
})

test_that("correct tool arguments pass parent-side validation", {
  tools <- list(
    securer_tool(
      "add", "Add numbers",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute("add(2, 3)")
  expect_equal(result, 5)
})
