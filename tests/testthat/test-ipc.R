test_that("Tool call pause/resume works", {
  add_fn <- function(a, b) a + b

  session <- SecureSession$new(tools = list(add = add_fn))
  on.exit(session$close())

  result <- session$execute(".securer_call_tool('add', a = 2, b = 3)")
  expect_equal(result, 5)
})

test_that("Multiple tool calls in sequence work", {
  add_fn <- function(a, b) a + b

  session <- SecureSession$new(tools = list(add = add_fn))
  on.exit(session$close())

  result <- session$execute("
    x <- .securer_call_tool('add', a = 1, b = 2)
    y <- .securer_call_tool('add', a = x, b = 10)
    y
  ")
  expect_equal(result, 13)
})

test_that("Unknown tool call returns error", {
  session <- SecureSession$new(tools = list())
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool('nonexistent', x = 1)"),
    "Unknown tool"
  )
})

test_that("Tool execution error is propagated", {
  bad_fn <- function() stop("tool failed")

  session <- SecureSession$new(tools = list(bad = bad_fn))
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool('bad')"),
    "tool failed"
  )
})
