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

test_that("dead session returns error ContentToolResult instead of throwing", {
  skip_if_not_installed("ellmer")

  session <- SecureSession$new(sandbox = FALSE)
  tool_def <- securer_as_ellmer_tool(session = session, timeout = 10)

  # Kill the session before calling the tool
  session$close()
  expect_false(session$is_alive())

  # Should return a ContentToolResult with error, not throw an R exception
  result <- tool_def(code = "1 + 1")
  expect_s3_class(result, "S7_object")
  expect_false(is.null(result@error))
  expect_match(result@error, "no longer alive")
})

test_that("format_tool_result truncates large data frames beyond 30 rows", {
  # Use a single-column data frame so print(max = 50) shows enough rows
  # to exceed the 30-line threshold (50 data rows + 1 header = 51 lines)
  big_df <- data.frame(x = seq_len(100))
  result <- format_tool_result(big_df)

  # Should contain the truncation indicator with the actual row count
  expect_match(result, "100 rows total")
  # The output should NOT contain all rows
  result_lines <- strsplit(result, "\n")[[1]]
  # 30 content lines + 1 truncation message = 31 lines
  expect_equal(length(result_lines), 31)
})

test_that("format_tool_result truncates long general output beyond 50 lines", {
  # Create a long list that prints > 50 lines
  long_list <- as.list(seq_len(200))
  result <- format_tool_result(long_list)

  # Should contain the truncation indicator
  expect_match(result, "output truncated")
  # The output should be capped
  result_lines <- strsplit(result, "\n")[[1]]
  # 50 lines + 1 truncation message = 51 lines
  expect_lte(length(result_lines), 51)
})


# --- sanitize_error_message() tests ---

test_that("sanitize_error_message replaces Unix file paths with [path]", {
  msg <- "cannot open file '/Users/john/data/secret.csv': No such file or directory"
  result <- sanitize_error_message(msg)
  expect_false(grepl("/Users/john", result))
  expect_match(result, "\\[path\\]")
  # Core error type is preserved
  expect_match(result, "cannot open file")
  expect_match(result, "No such file or directory")
})

test_that("sanitize_error_message replaces /home and /tmp paths", {
  msg <- "Error reading '/home/deploy/.config/db.conf'"
  result <- sanitize_error_message(msg)
  expect_false(grepl("/home/deploy", result))
  expect_match(result, "\\[path\\]")

  msg2 <- "File '/tmp/Rtmp1234abc/session/data.rds' not found"
  result2 <- sanitize_error_message(msg2)
  expect_false(grepl("/tmp/Rtmp", result2))
  expect_match(result2, "\\[path\\]")
})

test_that("sanitize_error_message replaces Windows file paths", {
  msg <- "cannot open C:\\Users\\admin\\Documents\\passwords.txt"
  result <- sanitize_error_message(msg)
  expect_false(grepl("admin", result))
  expect_match(result, "\\[path\\]")
})

test_that("sanitize_error_message replaces process IDs", {
  msg <- "process '12345' exited with status 1"
  result <- sanitize_error_message(msg)
  expect_false(grepl("12345", result))
  expect_match(result, "\\[pid\\]")

  msg2 <- "PID 67890 killed by signal 9"
  result2 <- sanitize_error_message(msg2)
  expect_false(grepl("67890", result2))
  expect_match(result2, "\\[pid\\]")
})

test_that("sanitize_error_message replaces IP addresses", {
  msg <- "connection to 192.168.1.42:5432 refused"
  result <- sanitize_error_message(msg)
  expect_false(grepl("192.168.1.42", result))
  expect_match(result, "\\[host\\]")
})

test_that("sanitize_error_message strips stack traces", {
  msg <- "Error in foo(): bad input\nCall stack:\n  1. bar()\n  2. baz()"
  result <- sanitize_error_message(msg)
  expect_false(grepl("Call stack", result))
  expect_false(grepl("bar()", result, fixed = TRUE))
  # But the core error is preserved
  expect_match(result, "bad input")
})

test_that("sanitize_error_message truncates long messages", {
  long_msg <- paste(rep("error ", 200), collapse = "")
  result <- sanitize_error_message(long_msg, max_length = 100)
  expect_true(nchar(result) <= 100)
  expect_match(result, "\\.\\.\\.$")
})

test_that("sanitize_error_message preserves simple error messages", {
  msg <- "object 'x' not found"
  result <- sanitize_error_message(msg)
  expect_equal(result, msg)
})

test_that("sanitize_error_message handles NULL and empty input", {
  expect_equal(sanitize_error_message(NULL), "Unknown error")
  expect_equal(sanitize_error_message(character(0)), "Unknown error")
})

test_that("ellmer tool sanitizes file paths in errors", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  # Use stop() to emit a path directly since callr may strip paths from
  # native R errors like readRDS()
  result <- tool_def(code = "stop('cannot open /Users/secret/data.rds')")
  expect_s3_class(result, "S7_object")
  expect_false(is.null(result@error))
  # The path should be sanitized
  expect_false(grepl("/Users/secret", result@error))
  expect_match(result@error, "\\[path\\]")
  # Core message is preserved
  expect_match(result@error, "cannot open")
})

test_that("ellmer tool sanitizes PIDs in errors", {
  skip_if_not_installed("ellmer")

  tool_def <- securer_as_ellmer_tool(sandbox = FALSE, timeout = 10)
  # Force an error with a PID-like message
  result <- tool_def(code = "stop('process 99999 crashed at PID 12345')")
  expect_false(grepl("99999", result@error))
  expect_false(grepl("12345", result@error))
})
