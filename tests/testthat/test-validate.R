# --- validate_code() unit tests ---

test_that("valid code passes validation", {
  result <- validate_code("1 + 1")
  expect_true(result$valid)
  expect_null(result$error)
  expect_length(result$warnings, 0)
})

test_that("multi-line valid code passes", {
  code <- "
    x <- 10
    y <- 20
    x + y
  "
  result <- validate_code(code)
  expect_true(result$valid)
  expect_null(result$error)
})

test_that("syntax error is caught", {
  result <- validate_code("if (TRUE {")
  expect_false(result$valid)
  expect_type(result$error, "character")
  expect_match(result$error, "unexpected", ignore.case = TRUE)
})

test_that("unmatched brace is caught", {
  result <- validate_code("function(x) { x + 1")
  expect_false(result$valid)
  expect_type(result$error, "character")
})

test_that("empty string is handled", {
  result <- validate_code("")
  expect_true(result$valid)
  expect_null(result$error)
})

test_that("whitespace-only string is handled", {
  result <- validate_code("   \n\n  ")
  expect_true(result$valid)
  expect_null(result$error)
})

test_that("NULL code is rejected", {
  expect_error(validate_code(NULL))
})

test_that("non-character code is rejected", {
  expect_error(validate_code(42))
})

test_that("dangerous patterns produce warnings", {
  result <- validate_code("system('ls')")
  expect_true(result$valid)  # still valid syntax
  expect_true(length(result$warnings) > 0)
  expect_true(any(grepl("system", result$warnings)))
})

test_that("system2 is flagged", {
  result <- validate_code("system2('echo', 'hello')")
  expect_true(result$valid)
  expect_true(length(result$warnings) > 0)
  expect_true(any(grepl("system2", result$warnings)))
})

test_that("shell() is flagged", {
  result <- validate_code("shell('dir')")
  expect_true(result$valid)
  expect_true(length(result$warnings) > 0)
})

test_that(".Internal() is flagged", {
  result <- validate_code(".Internal(inspect(1))")
  expect_true(result$valid)
  expect_true(length(result$warnings) > 0)
})

test_that("Sys.setenv() is flagged", {
  result <- validate_code("Sys.setenv(FOO = 'bar')")
  expect_true(result$valid)
  expect_true(length(result$warnings) > 0)
})

test_that("safe code has no warnings", {
  result <- validate_code("mean(c(1, 2, 3))")
  expect_true(result$valid)
  expect_length(result$warnings, 0)
})

test_that("multiple dangerous patterns produce multiple warnings", {
  result <- validate_code("system('ls'); system2('echo', 'hi')")
  expect_true(result$valid)
  expect_true(length(result$warnings) >= 2)
})

# --- Integration with SecureSession$execute(validate=...) ---

test_that("execute() rejects syntax errors by default", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute("if (TRUE {"),
    "syntax error"
  )
  # Session should still be alive after validation failure
  expect_true(session$is_alive())
})

test_that("execute() with validate=FALSE skips validation", {
  session <- SecureSession$new()
  on.exit(session$close())

  # This has a syntax error and should fail in the child process,
  # but the error should come from R's parser, not our validator
  expect_error(session$execute("if (TRUE {", validate = FALSE))
})

test_that("execute() validation does not affect valid code", {
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1", validate = TRUE)
  expect_equal(result, 2)
})

test_that("execute_r() rejects syntax errors", {
  expect_error(
    execute_r("if (TRUE {", sandbox = FALSE),
    "syntax error"
  )
})

test_that("execute_r() with validate=FALSE skips validation", {
  # Should still error, but from child process not from pre-validation
  expect_error(execute_r("if (TRUE {", validate = FALSE, sandbox = FALSE))
})
