test_that("verbose=FALSE produces no messages", {
  expect_silent({
    session <- SecureSession$new(verbose = FALSE)
    on.exit(session$close())
    result <- session$execute("1 + 1")
  })
  expect_equal(result, 2)
})

test_that("verbose=TRUE logs session start", {
  expect_message(
    session <- SecureSession$new(verbose = TRUE),
    "\\[securer\\] Session started"
  )
  on.exit(session$close())
})

test_that("verbose=TRUE logs tool calls", {
  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  session <- suppressMessages(
    SecureSession$new(tools = tools, verbose = TRUE)
  )
  on.exit(session$close())

  expect_message(
    session$execute("add(1, 2)"),
    "\\[securer\\] Tool call: add"
  )
})

test_that("verbose=TRUE logs execution complete", {
  session <- suppressMessages(SecureSession$new(verbose = TRUE))
  on.exit(session$close())

  expect_message(
    session$execute("1 + 1"),
    "\\[securer\\] Execution complete"
  )
})

test_that("verbose=TRUE logs session close", {
  session <- suppressMessages(SecureSession$new(verbose = TRUE))
  expect_message(session$close(), "\\[securer\\] Session closed")
})

test_that("verbose=TRUE logs tool result", {
  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  session <- suppressMessages(
    SecureSession$new(tools = tools, verbose = TRUE)
  )
  on.exit(session$close())

  expect_message(
    session$execute("add(1, 2)"),
    "\\[securer\\] Tool result: add"
  )
})

test_that("verbose=TRUE logs errors", {
  session <- suppressMessages(SecureSession$new(verbose = TRUE))
  on.exit(session$close())

  expect_message(
    try(session$execute("stop('test error')"), silent = TRUE),
    "\\[securer\\] Execution error"
  )
})

test_that("execute_r() passes verbose through", {
  expect_message(
    execute_r("1 + 1", sandbox = FALSE, verbose = TRUE),
    "\\[securer\\] Session started"
  )
})

test_that("default verbose is FALSE (no messages)", {
  expect_silent({
    session <- SecureSession$new()
    on.exit(session$close())
    session$execute("1 + 1")
  })
})
