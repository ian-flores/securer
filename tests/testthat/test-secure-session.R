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

# --- IPC message size limit tests (Finding 10) ---

test_that("max_ipc_message_size private field is 1MB", {
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  expect_equal(priv$max_ipc_message_size, 1048576L)
})

test_that("IPC message exceeding size limit is rejected", {
  # Register a tool so the parent enters the tool-call dispatch path
  tools <- list(
    securer_tool("echo", "Echo input", function(x) x, args = list(x = "character"))
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Lower the max_ipc_message_size to a small value so we can trigger the
  # check without sending a truly massive message over the UDS.
  priv <- session$.__enclos_env__$private
  priv$max_ipc_message_size <- 100L

  # A normal tool call via the wrapper will produce a JSON message > 100 bytes
  # (the JSON for tool_call + tool name + args easily exceeds 100 bytes).
  expect_error(
    session$execute('echo("hello world, this is a somewhat long argument string")'),
    "IPC message too large"
  )
})

# --- Malformed IPC JSON schema validation tests (Finding 10) ---

test_that("malformed IPC message (non-object JSON) is rejected", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Send a JSON array instead of a JSON object through the UDS
  expect_error(
    session$execute('
      processx::conn_write(.securer_env$conn, "[1, 2, 3]\n")
      processx::poll(list(.securer_env$conn), 10000)
      processx::conn_read_lines(.securer_env$conn, n = 1)
    '),
    "Malformed IPC message"
  )
})

test_that("malformed IPC message (missing type field) is rejected", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Send a JSON object without a 'type' field
  expect_error(
    session$execute('
      msg <- jsonlite::toJSON(list(tool = "foo"), auto_unbox = TRUE)
      processx::conn_write(.securer_env$conn, paste0(msg, "\n"))
      processx::poll(list(.securer_env$conn), 10000)
      processx::conn_read_lines(.securer_env$conn, n = 1)
    '),
    "'type' must be a scalar string"
  )
})

test_that("malformed IPC message (non-string type) is rejected", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Send a JSON object where 'type' is a number, not a string
  expect_error(
    session$execute('
      msg <- jsonlite::toJSON(list(type = 123, tool = "foo"), auto_unbox = TRUE)
      processx::conn_write(.securer_env$conn, paste0(msg, "\n"))
      processx::poll(list(.securer_env$conn), 10000)
      processx::conn_read_lines(.securer_env$conn, n = 1)
    '),
    "'type' must be a scalar string"
  )
})

test_that("malformed IPC tool_call (missing tool field) is rejected", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Send a tool_call message without a 'tool' field
  expect_error(
    session$execute('
      msg <- jsonlite::toJSON(list(type = "tool_call"), auto_unbox = TRUE)
      processx::conn_write(.securer_env$conn, paste0(msg, "\n"))
      processx::poll(list(.securer_env$conn), 10000)
      processx::conn_read_lines(.securer_env$conn, n = 1)
    '),
    "'tool' must be a scalar string"
  )
})

test_that("malformed IPC tool_call (args not a list) is rejected", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Send a tool_call where 'args' is a string instead of an object.
  # Build the JSON using paste0 to avoid quoting headaches.
  expect_error(
    session$execute('
      dq <- rawToChar(as.raw(0x22))
      raw <- paste0("{", dq, "type", dq, ":", dq, "tool_call", dq,
                    ",", dq, "tool", dq, ":", dq, "foo", dq,
                    ",", dq, "args", dq, ":", dq, "bad", dq, "}\n")
      processx::conn_write(.securer_env$conn, raw)
      processx::poll(list(.securer_env$conn), 10000)
      processx::conn_read_lines(.securer_env$conn, n = 1)
    '),
    "'args' must be a list or null"
  )
})

# --- Tool name regex sanitization tests (Finding 10) ---

test_that("injection-style tool name is sanitized to <invalid>", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Try calling a tool with a name containing shell injection characters.
  # The parent regex should replace it with "<invalid>" and then respond
  # with "Unknown tool: <invalid>".
  expect_error(
    session$execute('.securer_call_tool("x; system(\'id\')")'),
    "Unknown tool"
  )
})

test_that("tool name with leading digit is sanitized", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Tool names must match ^[A-Za-z.][A-Za-z0-9_.]*$ — leading digit is invalid
  expect_error(
    session$execute('.securer_call_tool("123bad")'),
    "Unknown tool"
  )
})

test_that("tool name with special characters is sanitized", {
  session <- SecureSession$new()
  on.exit(session$close())

  # Slashes, dashes, and other special chars should be rejected
  expect_error(
    session$execute('.securer_call_tool("../../etc/passwd")'),
    "Unknown tool"
  )
})

test_that("valid tool name pattern is accepted", {
  # Ensure the regex doesn't reject legitimate R-style names
  tools <- list(
    securer_tool("my.tool_v2", "A tool", function() 42, args = list())
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute("my.tool_v2()")
  expect_equal(result, 42)
})

# --- Non-list args coercion tests (Finding 5) ---

test_that("non-list args from child are rejected", {
  # When a child sends a tool_call with 'args' as a string (not an
  # object/list), the parent's schema validation rejects it.  The
  # coercion at lines 422-425 is a defense-in-depth fallback behind
  # the schema check.  Either way, the parent handles it gracefully
  # instead of crashing.
  session <- SecureSession$new()
  on.exit(session$close())

  # Craft a raw tool_call where args is a string (not a list/object).
  # Build JSON using paste0 with rawToChar to avoid quoting issues.
  expect_error(
    session$execute('
      dq <- rawToChar(as.raw(0x22))
      raw <- paste0("{", dq, "type", dq, ":", dq, "tool_call", dq,
                    ",", dq, "tool", dq, ":", dq, "ping", dq,
                    ",", dq, "args", dq, ":", dq, "not_a_list", dq, "}\n")
      processx::conn_write(.securer_env$conn, raw)
      processx::poll(list(.securer_env$conn), 10000)
      processx::conn_read_lines(.securer_env$conn, n = 1)
    '),
    "'args' must be a list or null"
  )
})

test_that("tool_call with empty object args works", {
  # Verify the args coercion path: when args is an empty object {},
  # jsonlite parses it as a named list (list()), which passes both the
  # schema check and the coercion guard.  The tool should execute normally.
  tools <- list(
    securer_tool("ping", "Ping", function() "pong", args = list())
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Send a raw tool_call JSON with args as an empty object.
  result <- session$execute('
    dq <- rawToChar(as.raw(0x22))
    raw <- paste0("{", dq, "type", dq, ":", dq, "tool_call", dq,
                  ",", dq, "tool", dq, ":", dq, "ping", dq,
                  ",", dq, "args", dq, ":{}}\n")
    processx::conn_write(.securer_env$conn, raw)
    processx::poll(list(.securer_env$conn), 10000)
    resp <- processx::conn_read_lines(.securer_env$conn, n = 1)
    jsonlite::fromJSON(resp, simplifyVector = FALSE)$value
  ')
  expect_equal(result, "pong")
})
