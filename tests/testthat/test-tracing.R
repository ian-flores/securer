test_that("execute_r emits span when trace active", {
  skip_if_not_installed("securetrace")

  result <- securetrace::with_trace("test-execute", {
    execute_r("1 + 1", sandbox = FALSE)
  })

  expect_equal(result, 2)
})

test_that("execute_r works without trace", {
  result <- execute_r("1 + 1", sandbox = FALSE)
  expect_equal(result, 2)
})

test_that("tool calls emit spans when trace active", {
  skip_if_not_installed("securetrace")

  tools <- list(
    securer_tool("add", "Add numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )

  result <- securetrace::with_trace("test-tools", {
    execute_r("add(2, 3)", tools = tools, sandbox = FALSE)
  })

  expect_equal(result, 5)
})
