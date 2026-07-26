test_that("execute_r emits spans when tracing is enabled", {
  skip_if_not_installed("otel")
  skip_if_not_installed("otelsdk")

  rec <- otelsdk::with_otel_record(
    {
      execute_r("1 + 1", sandbox = FALSE)
    },
    what = "traces"
  )

  expect_equal(rec$value, 2)
  expect_true("securer::execute_r" %in% names(rec$traces))
  expect_true("securer::SecureSession$execute" %in% names(rec$traces))
})

test_that("execute_r works without tracing", {
  result <- execute_r("1 + 1", sandbox = FALSE)
  expect_equal(result, 2)
})

test_that("tool calls emit spans when tracing is enabled", {
  skip_if_not_installed("otel")
  skip_if_not_installed("otelsdk")

  tools <- list(
    securer_tool("add", "Add numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )

  rec <- otelsdk::with_otel_record(
    {
      execute_r("add(2, 3)", tools = tools, sandbox = FALSE)
    },
    what = "traces"
  )

  expect_equal(rec$value, 5)
  expect_true("securer::tool/add" %in% names(rec$traces))
})

test_that("tracing helpers are inert when tracing is disabled", {
  # No OpenTelemetry SDK/exporter is configured in the test environment,
  # so tracing must be off and the helpers must fall through cleanly.
  expect_false(.trace_active())
  expect_identical(.with_span("securer::noop", 42L), 42L)
  expect_null(.span_event("noop", list(key = "value")))

  # Full execution path with tracing disabled
  tools <- list(
    securer_tool("add", "Add numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )
  expect_equal(execute_r("add(2, 3)", tools = tools, sandbox = FALSE), 5)
})
