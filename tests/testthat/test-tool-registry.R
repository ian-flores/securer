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

# --- Type checking tests ---

test_that("generate_type_checks() produces validation code for typed args", {
  code <- generate_type_checks("add", list(a = "numeric", b = "numeric"))
  expect_true(grepl("is.numeric(a)", code, fixed = TRUE))
  expect_true(grepl("is.numeric(b)", code, fixed = TRUE))
  expect_true(grepl("Tool 'add': argument 'a' must be numeric", code, fixed = TRUE))
})

test_that("generate_type_checks() skips args without type annotations", {
  code <- generate_type_checks("my_tool", list(x = "numeric", y = NULL))
  expect_true(grepl("is.numeric(x)", code, fixed = TRUE))
  expect_false(grepl("argument 'y'", code, fixed = TRUE))
})

test_that("generate_type_checks() returns empty for no typed args", {
  code <- generate_type_checks("my_tool", list(x = NULL, y = ""))
  expect_equal(code, "")
})

test_that("generate_type_checks() skips unknown type annotations", {
  code <- generate_type_checks("my_tool", list(x = "foobar"))
  expect_equal(code, "")
})

test_that("generate_type_checks() supports all standard types", {
  types <- c("numeric", "character", "logical", "integer", "list", "data.frame")
  fns <- c("is.numeric", "is.character", "is.logical", "is.integer", "is.list", "is.data.frame")
  for (i in seq_along(types)) {
    args <- setNames(list(types[i]), "x")
    code <- generate_type_checks("t", args)
    expect_true(grepl(fns[i], code, fixed = TRUE),
                info = paste("type:", types[i]))
  }
})

test_that("generate_tool_wrappers() includes type checks in wrapper code", {
  tools <- list(
    securer_tool(
      "add", "Add numbers",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  code <- generate_tool_wrappers(tools)
  expect_true(grepl("is.numeric(a)", code, fixed = TRUE))
  expect_true(grepl("is.numeric(b)", code, fixed = TRUE))
  expect_true(grepl(".securer_call_tool", code, fixed = TRUE))
})

test_that("generate_tool_wrappers() skips checks for tools with no typed args", {
  tools <- list(
    securer_tool(
      "ping", "Ping",
      function() "pong",
      args = list()
    )
  )
  code <- generate_tool_wrappers(tools)
  expect_false(grepl("is\\.", code))
})

test_that("Type checking passes for correct types end-to-end", {
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

test_that("Type checking rejects wrong types end-to-end", {
  tools <- list(
    securer_tool(
      "add", "Add numbers",
      function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  expect_error(
    session$execute('add("hello", 3)'),
    "Tool 'add': argument 'a' must be numeric, got character"
  )
})

test_that("Type checking validates multiple args independently", {
  tools <- list(
    securer_tool(
      "greet", "Greet",
      function(name, times) paste(rep(name, times), collapse = " "),
      args = list(name = "character", times = "numeric")
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Correct types work
  result <- session$execute('greet("hi", 3)')
  expect_equal(result, "hi hi hi")

  # Wrong first arg
  expect_error(
    session$execute("greet(123, 3)"),
    "Tool 'greet': argument 'name' must be character"
  )

  # Wrong second arg
  expect_error(
    session$execute('greet("hi", "three")'),
    "Tool 'greet': argument 'times' must be numeric"
  )
})

test_that("Type checking skips unannotated args end-to-end", {
  tools <- list(
    securer_tool(
      "flexible", "Flexible tool",
      function(a, b) paste(a, b),
      args = list(a = "character", b = NULL)
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # b has no type annotation so any type is accepted
  result <- session$execute('flexible("hello", 42)')
  expect_equal(result, "hello 42")
})
