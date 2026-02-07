test_that("securer_tool() creates valid tool objects", {
  tool <- securer_tool(
    "add", "Add two numbers",
    function(a, b) a + b,
    args = list(a = "numeric", b = "numeric")
  )
  expect_s3_class(tool, "securer_tool")
  expect_equal(tool$name, "add")
  expect_equal(tool$description, "Add two numbers")
  expect_true(is.function(tool$fn))
})

test_that("securer_tool() validates inputs", {
  expect_error(securer_tool("", "desc", identity))
  expect_error(securer_tool(123, "desc", identity))
  expect_error(securer_tool("name", "desc", "not_a_function"))
})

test_that("validate_tools() detects duplicates", {
  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b),
    securer_tool("add", "Add again", function(a, b) a + b)
  )
  expect_error(validate_tools(tools), "Duplicate")
})

test_that("validate_tools() accepts legacy named function lists", {
  tools <- list(add = function(a, b) a + b)
  result <- validate_tools(tools)
  expect_true(is.function(result$add))
})

test_that("generate_tool_wrappers() creates callable code", {
  tools <- list(
    securer_tool(
      "get_weather", "Get weather",
      function(city) list(temp = 72),
      args = list(city = "character")
    )
  )
  code <- generate_tool_wrappers(tools)
  expect_true(grepl("get_weather", code))
  expect_true(grepl(".securer_call_tool", code))
})

test_that("Tool wrappers work end-to-end via SecureSession", {
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

test_that("Multiple tools with wrappers work", {
  tools <- list(
    securer_tool(
      "add", "Add",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    ),
    securer_tool(
      "multiply", "Multiply",
      function(a, b) a * b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute("
    x <- add(2, 3)
    y <- multiply(x, 4)
    y
  ")
  expect_equal(result, 20)
})

test_that("Tool wrappers compose with regular R code", {
  tools <- list(
    securer_tool(
      "get_data", "Get a value",
      function(key) {
        switch(key, a = 10, b = 20, 0)
      },
      args = list(key = "character")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute('
    vals <- vapply(c("a", "b", "c"), get_data, numeric(1))
    sum(vals)
  ')
  expect_equal(result, 30)
})

test_that("Legacy tool format still works with SecureSession", {
  # Backward compatibility: named list of functions
  session <- SecureSession$new(tools = list(add = function(a, b) a + b))
  on.exit(session$close())

  result <- session$execute(".securer_call_tool('add', a = 10, b = 5)")
  expect_equal(result, 15)
})
