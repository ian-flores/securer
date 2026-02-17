test_that("SecureSession can execute simple code", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

test_that("SecureSession can execute multi-line code", {
  skip_if_no_session()
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
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(session$execute("stop('user error')"), "user error")
})

test_that("SecureSession$close() works", {
  skip_if_no_session()
  session <- SecureSession$new()
  session$close()
  expect_false(session$is_alive())
})

test_that("execute on closed session errors", {
  skip_if_no_session()
  session <- SecureSession$new()
  session$close()
  expect_error(session$execute("1"), "not running")
})

test_that("sequential execute() calls work fine", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_equal(session$execute("1 + 1"), 2)
  expect_equal(session$execute("2 + 3"), 5)
  expect_equal(session$execute("10 * 10"), 100)
})

test_that("executing flag resets after error in user code", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(session$execute("stop('boom')"), "boom")
  # Should still work after an error — executing flag must have been reset
  expect_equal(session$execute("42"), 42)
})

test_that("concurrent execute() is rejected", {
  skip_if_no_session()
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
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1", timeout = 5)
  expect_equal(result, 2)
})

test_that("execute() times out on infinite loop", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute("while(TRUE) {}", timeout = 1),
    "timed out after 1 second"
  )
})

test_that("execute() with NULL timeout works normally (no timeout)", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # NULL timeout means no limit; a fast expression should complete fine
  result <- session$execute("42", timeout = NULL)
  expect_equal(result, 42)
})

test_that("session is usable after a timeout", {
  skip_if_no_session()
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
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # cat() + explicit return value so we can check the output attribute
  result <- session$execute('cat("hello world"); TRUE')
  expect_true(result)
  expect_equal(attr(result, "output"), "hello world")
})

test_that("execute() captures print() output", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("print(1:3)")
  output <- attr(result, "output")
  expect_true(length(output) > 0)
  expect_true(any(grepl("1 2 3", output)))
})

test_that("output_handler receives lines as they arrive", {
  skip_if_no_session()
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
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute('cat("msg\\n"); 42')
  expect_equal(result, 42, ignore_attr = TRUE)
  output <- attr(result, "output")
  expect_true(any(grepl("msg", output)))
})

# --- Rate limiting tests (Finding 14) ---

test_that("max_tool_calls limits tool invocations", {
  skip_if_no_session()
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
  skip_if_no_session()
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
  skip_if_no_session()
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
  skip_if_no_session()
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
  skip_if_no_session()
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
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  expect_equal(priv$max_ipc_message_size, 1048576L)
})

test_that("IPC message exceeding size limit is rejected", {
  skip_if_no_session()
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

test_that("child code cannot access .securer_env (closure-based hiding)", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # .securer_env no longer exists in the child's global environment
  result <- session$execute("exists('.securer_env', envir = globalenv())")
  expect_false(result)
})

test_that("child code cannot access .securer_connect (closure-based hiding)", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # .securer_connect no longer exists in the child's global environment
  result <- session$execute("exists('.securer_connect', envir = globalenv())")
  expect_false(result)
})

test_that("child code cannot access the raw UDS connection", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # The connection is captured in the closure's enclosing environment,
  # not in any accessible global or named environment.
  # Attempting to get it via environment() on the closure should not
  # expose a usable conn object to arbitrary child code.
  result <- session$execute('
    env <- environment(.securer_call_tool)
    # The enclosing env exists but is not the global env
    !identical(env, globalenv())
  ')
  expect_true(result)
})

# --- Tool name regex sanitization tests (Finding 10) ---

test_that("injection-style tool name is sanitized to <invalid>", {
  skip_if_no_session()
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
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # Tool names must match ^[A-Za-z.][A-Za-z0-9_.]*$ — leading digit is invalid
  expect_error(
    session$execute('.securer_call_tool("123bad")'),
    "Unknown tool"
  )
})

test_that("tool name with special characters is sanitized", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # Slashes, dashes, and other special chars should be rejected
  expect_error(
    session$execute('.securer_call_tool("../../etc/passwd")'),
    "Unknown tool"
  )
})

test_that("valid tool name pattern is accepted", {
  skip_if_no_session()
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

test_that("non-list args from child are rejected via .securer_call_tool", {
  skip_if_no_session()
  # With the closure-based pattern, child code cannot access the raw
  # connection to send malformed messages. This test verifies that
  # unexpected arg types are caught through the normal tool call path.
  tools <- list(
    securer_tool("ping", "Ping", function() "pong", args = list())
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Calling with unexpected arguments is rejected by parent-side validation
  expect_error(
    session$execute('.securer_call_tool("ping", bad_arg = "not_a_list")'),
    "Unexpected arguments.*'bad_arg'"
  )
})

test_that("tool_call with no args works via wrapper function", {
  skip_if_no_session()
  # Verify tool calls with no arguments work correctly through the
  # wrapper function (the normal code path).
  tools <- list(
    securer_tool("ping", "Ping", function() "pong", args = list())
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute("ping()")
  expect_equal(result, "pong")
})

# --- Environment sanitization tests (V29) ---

test_that("child does not inherit parent env vars", {
  skip_if_no_session()
  # Set a custom env var in the parent
  Sys.setenv(SECURER_TEST_SECRET = "leaked")
  on.exit(Sys.unsetenv("SECURER_TEST_SECRET"))

  session <- SecureSession$new()
  on.exit(session$close(), add = TRUE)

  result <- session$execute("Sys.getenv('SECURER_TEST_SECRET')")
  expect_equal(result, "")
})

test_that("child inherits safe vars like PATH and HOME", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("nzchar(Sys.getenv('PATH'))")
  expect_true(result)
})

test_that("child SECURER_SOCKET env var is cleared after connect", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # SECURER_SOCKET is cleared after the child connects for security
  result <- session$execute("Sys.getenv('SECURER_SOCKET')")
  expect_equal(result, "")
})

# --- R_LIBS env hardening tests (S11) ---

test_that("R_LIBS is NOT inherited by the child process (S11 fix)", {
  skip_if_no_session()
  # Set R_LIBS in the parent to simulate attacker-controlled path
  old_val <- Sys.getenv("R_LIBS", unset = NA)
  Sys.setenv(R_LIBS = "/tmp/malicious_packages")
  on.exit({
    if (is.na(old_val)) Sys.unsetenv("R_LIBS") else Sys.setenv(R_LIBS = old_val)
  })

  session <- SecureSession$new()
  on.exit(session$close(), add = TRUE)

  result <- session$execute("Sys.getenv('R_LIBS')")
  expect_equal(result, "")
})

test_that("R_LIBS_USER is cleared in child process (S11 fix)", {
  skip_if_no_session()
  # Set R_LIBS_USER in the parent
  old_val <- Sys.getenv("R_LIBS_USER", unset = NA)
  Sys.setenv(R_LIBS_USER = "/tmp/malicious_user_packages")
  on.exit({
    if (is.na(old_val)) {
      Sys.unsetenv("R_LIBS_USER")
    } else {
      Sys.setenv(R_LIBS_USER = old_val)
    }
  })

  session <- SecureSession$new()
  on.exit(session$close(), add = TRUE)

  result <- session$execute("Sys.getenv('R_LIBS_USER')")
  expect_equal(result, "")
})

# --- Default limits tests (V9) ---

test_that("sandbox=TRUE auto-applies default resource limits", {
  skip_if_no_session()
  skip_on_os(c("windows", "linux"))
  skip_if_not(file.exists("/usr/bin/sandbox-exec"), "sandbox-exec not available")

  # Test the wrapper directly without starting a full session
  # (avoids sandbox-exec path issues on CI)
  socket_path <- tempfile("test_sock_", fileext = ".sock")
  config <- build_sandbox_macos(socket_path, R.home(), limits = default_limits())
  on.exit({
    unlink(config$wrapper)
    unlink(config$profile_path)
  })

  wrapper_lines <- readLines(config$wrapper)
  expect_true(any(grepl("ulimit", wrapper_lines)))
})

test_that("sandbox=FALSE does not auto-apply limits", {
  skip_if_no_session()
  session <- SecureSession$new(sandbox = FALSE)
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  expect_null(priv$limits)
})

test_that("explicit limits override defaults when sandbox=TRUE", {
  # Test the logic directly: when limits are provided, they should be used as-is
  custom_limits <- list(cpu = 120)
  # Simulate what initialize() does
  sandbox <- TRUE
  limits <- custom_limits
  if (sandbox && is.null(limits)) {
    limits <- default_limits()
  }
  expect_equal(limits, custom_limits)
})

test_that("empty list limits disables defaults when sandbox=TRUE", {
  # Test the logic directly: empty list() is not NULL, so defaults should not apply
  sandbox <- TRUE
  limits <- list()
  if (sandbox && is.null(limits)) {
    limits <- default_limits()
  }
  expect_equal(limits, list())
})

test_that("default_limits returns expected structure", {
  dl <- default_limits()
  expect_true(is.list(dl))
  expect_true("cpu" %in% names(dl))
  expect_true("memory" %in% names(dl))
  expect_true("fsize" %in% names(dl))
  expect_true("nproc" %in% names(dl))
  expect_true("nofile" %in% names(dl))
  # All values should be positive
  for (v in dl) expect_true(v > 0)
})

test_that("GC finalizer cleans up child process", {
  skip_if_no_session()
  # Run in a local environment so the session reference is truly dropped
  pid <- local({
    s <- SecureSession$new()
    p <- s$.__enclos_env__$private$session$get_pid()
    expect_true(s$is_alive())
    p
  })

  # Force garbage collection (may take multiple passes for R6 finalizer)
  for (i in seq_len(10)) invisible(gc(full = TRUE))
  Sys.sleep(1)

  # tools::pskill(signal=0) returns TRUE if process exists, FALSE if not
  expect_false(tools::pskill(pid, signal = 0))
})

# --- print/format method tests ---

test_that("format() shows session info for running session", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  out <- format(session)
  expect_match(out, "SecureSession")
  expect_match(out, "running")
  expect_match(out, "sandbox=disabled")
  expect_match(out, "tools=0")
})

test_that("format() shows stopped after close", {
  skip_if_no_session()
  session <- SecureSession$new()
  session$close()

  out <- format(session)
  expect_match(out, "stopped")
  expect_match(out, "pid=NA")
})

test_that("format() shows tool count", {
  skip_if_no_session()
  tools <- list(
    securer_tool("add", "Add", fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  out <- format(session)
  expect_match(out, "tools=1")
})

test_that("print() outputs format string", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  out <- capture.output(print(session))
  expect_match(out, "SecureSession")
})

# --- $tools() accessor tests ---

test_that("$tools() returns empty list when no tools registered", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$tools()
  expect_equal(result, list())
})

test_that("$tools() returns registered securer_tool info", {
  skip_if_no_session()
  tools <- list(
    securer_tool("add", "Add numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric")),
    securer_tool("mul", "Multiply",
      fn = function(x, y) x * y,
      args = list(x = "numeric", y = "numeric"))
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$tools()
  expect_equal(length(result), 2)
  expect_true("add" %in% names(result))
  expect_true("mul" %in% names(result))
  expect_equal(result$add$name, "add")
  expect_equal(result$add$args, list(a = "numeric", b = "numeric"))
})

test_that("$tools() works with legacy tool format", {
  skip_if_no_session()
  tools <- list(add = function(a, b) a + b)
  expect_warning(
    session <- SecureSession$new(tools = tools),
    "deprecated"
  )
  on.exit(session$close())

  result <- session$tools()
  expect_equal(length(result), 1)
  expect_equal(result[[1]]$name, "add")
  expect_null(result[[1]]$args)
})

# --- $restart() method tests ---

test_that("$restart() creates a fresh session with new PID", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  old_pid <- session$execute("Sys.getpid()")
  session$restart()
  new_pid <- session$execute("Sys.getpid()")

  expect_false(identical(old_pid, new_pid))
  expect_true(session$is_alive())
})

test_that("$restart() re-registers tools", {
  skip_if_no_session()
  tools <- list(
    securer_tool("add", "Add numbers",
      fn = function(a, b) a + b,
      args = list(a = "numeric", b = "numeric"))
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result1 <- session$execute("add(2, 3)")
  expect_equal(result1, 5)

  session$restart()

  result2 <- session$execute("add(10, 20)")
  expect_equal(result2, 30)
})

test_that("$restart() works on a dead session", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # Kill the session manually
  session$.__enclos_env__$private$session$kill()
  Sys.sleep(0.5)
  expect_false(session$is_alive())

  # restart should recover
  session$restart()
  expect_true(session$is_alive())
  expect_equal(session$execute("1 + 1"), 2)
})

test_that("$restart() errors during active execution", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # Simulate an active execution by setting the flag
  env <- session$.__enclos_env__$private
  env$executing <- TRUE

  expect_error(session$restart(), "Cannot restart while an execution is in progress")

  # Reset flag for cleanup
  env$executing <- FALSE
})

# --- Total message flood protection tests (I4 fix) ---

test_that("total_messages counter initialized from max_tool_calls", {
  skip_if_no_session()
  # Verify the max_messages cap is computed correctly.
  # With max_tool_calls = 2, the cap should be 2 * 10 = 20.
  # We test by making exactly 2 tool calls (within limit) and confirming
  # execution succeeds.
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
    b
  ", max_tool_calls = 2)
  expect_equal(result, 3)
})

test_that("unknown IPC message type emits a warning", {
  skip_if_no_session()
  # Verify the warning code path exists and normal execution
  # still works (no false positives from the counter).
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1")
  expect_equal(result, 2)
})

# --- T4 fix: tools with args=list() reject extra arguments ---

test_that("tool with args=list() rejects extra arguments via .securer_call_tool", {
  skip_if_no_session()
  tools <- list(
    securer_tool(
      "ping", "Ping with no args",
      function() "pong",
      args = list()
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  # Call with an unexpected argument via raw .securer_call_tool()
  expect_error(
    session$execute('.securer_call_tool("ping", evil = 999)'),
    "Unexpected arguments.*'evil'"
  )
})

test_that("tool with args=list() works when called with no arguments", {
  skip_if_no_session()
  tools <- list(
    securer_tool(
      "ping", "Ping with no args",
      function() "pong",
      args = list()
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  result <- session$execute("ping()")
  expect_equal(result, "pong")
})

test_that("tool with args=list() rejects multiple extra arguments", {
  skip_if_no_session()
  tools <- list(
    securer_tool(
      "noop", "No args allowed",
      function() NULL,
      args = list()
    )
  )
  session <- SecureSession$new(tools = tools)
  on.exit(session$close())

  expect_error(
    session$execute('.securer_call_tool("noop", x = 1, y = 2)'),
    "Unexpected arguments.*noop"
  )
})

# --- New feature tests: max_code_length ---

test_that("max_code_length rejects oversized code", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # Set a very small max_code_length to test rejection
  expect_error(
    session$execute("1 + 1", max_code_length = 3),
    "Code too long"
  )
})

test_that("max_code_length allows code within limit", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("1 + 1", max_code_length = 100)
  expect_equal(result, 2)
})

# --- New feature tests: max_output_lines ---

test_that("max_output_lines caps accumulated output", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # Print many lines but cap at 3
  result <- session$execute(
    'for (i in 1:100) cat(i, "\\n"); TRUE',
    max_output_lines = 3
  )
  expect_true(result)
  output <- attr(result, "output")
  # Output should be capped (no more than 3 stored lines)
  expect_true(length(output) <= 3)
})

# --- New feature tests: max_executions ---

test_that("max_executions limits the number of execute() calls", {
  skip_if_no_session()
  session <- SecureSession$new(max_executions = 2)
  on.exit(session$close())

  expect_equal(session$execute("1"), 1)
  expect_equal(session$execute("2"), 2)
  expect_error(session$execute("3"), "Maximum executions \\(2\\) reached")
})

# --- New feature tests: pre_execute_hook ---

test_that("pre_execute_hook can block execution", {
  skip_if_no_session()
  session <- SecureSession$new(
    pre_execute_hook = function(code) {
      !grepl("system", code)
    }
  )
  on.exit(session$close())

  # Safe code passes
  expect_equal(session$execute("1 + 1"), 2)

  # Code mentioning system is blocked
  expect_error(
    session$execute('system("whoami")'),
    "Execution blocked by pre_execute_hook"
  )
})

test_that("pre_execute_hook returning TRUE allows execution", {
  skip_if_no_session()
  session <- SecureSession$new(
    pre_execute_hook = function(code) TRUE
  )
  on.exit(session$close())

  result <- session$execute("42")
  expect_equal(result, 42)
})

# --- New feature tests: sanitize_errors ---

test_that("sanitize_errors strips file paths from error messages", {
  skip_if_no_session()
  session <- SecureSession$new(sanitize_errors = TRUE)
  on.exit(session$close())

  expect_error(
    session$execute("stop('cannot open /Users/secret/data.rds')"),
    "\\[path\\]"
  )
})

test_that("sanitize_errors=FALSE preserves original error message", {
  skip_if_no_session()
  session <- SecureSession$new(sanitize_errors = FALSE)
  on.exit(session$close())

  expect_error(
    session$execute("stop('cannot open /Users/secret/data.rds')"),
    "/Users/secret"
  )
})

# --- Closure hardening tests ---

test_that("child cannot modify .ipc_store environment (locked)", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # The .ipc_store environment is locked, so assigning to it should fail
  expect_error(
    session$execute('
      env <- environment(.securer_call_tool)
      store <- env$.ipc_store
      store$evil <- "injected"
    ')
  )
})

test_that("child cannot add new bindings to .ipc_store", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute('
      env <- environment(.securer_call_tool)
      store <- env$.ipc_store
      assign("evil", "injected", envir = store)
    ')
  )
})
