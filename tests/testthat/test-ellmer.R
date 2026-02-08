test_that("securer_as_ellmer_tool() requires ellmer", {
  # This test just checks the function exists and the API is correct.
  # If ellmer is not installed, the function should error clearly.
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE)
  expect_s3_class(tool_def, "S7_object")
  expect_true(is.function(tool_def))
})

test_that("ellmer tool has correct name and description", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE)
  expect_equal(tool_def@name, "execute_r_code")
  expect_match(tool_def@description, "Execute R code")
})

test_that("ellmer tool executes simple code", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  result <- tool_def(code = "1 + 1")
  expect_equal(result, "2")
})

test_that("ellmer tool executes code returning a vector", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  result <- tool_def(code = "c(1, 2, 3)")
  expect_match(result, "1 2 3")
})

test_that("ellmer tool returns error as ContentToolResult on failure", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  result <- tool_def(code = "stop('test error')")
  expect_s3_class(result, "S7_object")
  expect_false(is.null(result@error))
  expect_match(result@error, "test error")
})

test_that("ellmer tool works with securer tools", {
  skip_if_not_installed("ellmer")

  tools <- list(
    securer_tool("add", "Add numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )
  tool_def <- securer_as_ellmer_tool(tools = tools, sandbox = FALSE, timeout = 10)
  result <- tool_def(code = "add(10, 20)")
  expect_equal(result, "30")
})

test_that("ellmer tool works with pre-existing session", {
  skip_if_not_installed("ellmer")

  session <- SecureSession$new(sandbox = FALSE)
  on.exit(session$close())

  tool_def <- securer_as_ellmer_tool(session = session, timeout = 10)
  result <- tool_def(code = "42")
  expect_equal(result, "42")

  # Session should still be alive (we own it, not the tool)
  expect_true(session$is_alive())
})

test_that("ellmer tool handles timeout", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 1)
  result <- tool_def(code = "Sys.sleep(60)")
  expect_s3_class(result, "S7_object")
  expect_false(is.null(result@error))
  expect_match(result@error, "timed out|timeout", ignore.case = TRUE)
})

test_that("ellmer tool handles invisible results", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  result <- tool_def(code = "invisible(42)")
  expect_equal(result, "42")
})

test_that("ellmer tool returns data frame results", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  result <- tool_def(code = "data.frame(x = 1:3, y = letters[1:3])")
  expect_match(result, "x")
  expect_match(result, "y")
})

test_that("format_tool_result handles various types", {
  expect_equal(format_tool_result(NULL), "NULL")
  expect_equal(format_tool_result(42), "42")
  expect_equal(format_tool_result("hello"), "hello")
  expect_match(format_tool_result(1:5), "1 2 3 4 5")
  expect_match(format_tool_result(data.frame(a = 1)), "a")
})
