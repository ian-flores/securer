test_that("Tool call pause/resume works", {
  skip_if_no_session()
  add_fn <- function(a, b) a + b

  expect_warning(
    session <- SecureSession$new(tools = list(add = add_fn)),
    "deprecated"
  )
  on.exit(session$close())

  result <- session$execute(".securer_call_tool('add', a = 2, b = 3)")
  expect_equal(result, 5)
})

test_that("Multiple tool calls in sequence work", {
  skip_if_no_session()
  add_fn <- function(a, b) a + b

  expect_warning(
    session <- SecureSession$new(tools = list(add = add_fn)),
    "deprecated"
  )
  on.exit(session$close())

  result <- session$execute("
    x <- .securer_call_tool('add', a = 1, b = 2)
    y <- .securer_call_tool('add', a = x, b = 10)
    y
  ")
  expect_equal(result, 13)
})

test_that("Unknown tool call returns error", {
  skip_if_no_session()
  session <- SecureSession$new(tools = list())
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool('nonexistent', x = 1)"),
    "Unknown tool"
  )
})

test_that("Tool execution error is propagated", {
  skip_if_no_session()
  bad_fn <- function() stop("tool failed")

  expect_warning(
    session <- SecureSession$new(tools = list(bad = bad_fn)),
    "deprecated"
  )
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool('bad')"),
    "tool failed"
  )
})

test_that("Overwriting .securer_call_tool in child is prevented", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool <- function(...) 'hijacked'"),
    "cannot change value of locked binding"
  )
})

test_that("unlockBinding is shadowed in child", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute('unlockBinding(".securer_call_tool", globalenv())'),
    "unlockBinding is not permitted in secure sessions"
  )
})

test_that("Overwriting unlockBinding in child is prevented", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute("unlockBinding <- function(...) 'hijacked'"),
    "cannot change value of locked binding"
  )
})

test_that("SECURER_TOKEN env var is cleared in child after auth", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("Sys.getenv('SECURER_TOKEN')")
  expect_equal(result, "")
})

test_that("SECURER_SOCKET env var is cleared in child after connect", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  result <- session$execute("Sys.getenv('SECURER_SOCKET')")
  expect_equal(result, "")
})

test_that("Tool calls still work after bindings are locked", {
  skip_if_no_session()
  add_fn <- function(a, b) a + b

  expect_warning(
    session <- SecureSession$new(tools = list(add = add_fn)),
    "deprecated"
  )
  on.exit(session$close())

  result <- session$execute(".securer_call_tool('add', a = 10, b = 20)")
  expect_equal(result, 30)
})

# --- Socket directory isolation tests (Finding 8) ---

test_that("socket lives in a private directory with 0700 permissions", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  socket_dir <- priv$socket_dir
  socket_path <- priv$socket_path

  # Socket directory exists and is a directory
  expect_true(dir.exists(socket_dir))

  # Socket path is inside the private directory
  # Use normalizePath to handle Windows backslash vs forward slash
  expect_equal(
    normalizePath(dirname(socket_path), mustWork = FALSE),
    normalizePath(socket_dir, mustWork = FALSE)
  )
  expect_equal(basename(socket_path), "ipc.sock")

  # Directory permissions are 0700 (owner only)
  # Windows does not support Unix file permissions; skip the check there
  if (.Platform$OS.type != "windows") {
    info <- file.info(socket_dir)
    mode <- as.integer(info$mode)
    # 0700 in octal = 448 in decimal
    expect_equal(bitwAnd(mode, 511L), 448L)
  }
})

test_that("socket directory is cleaned up on close", {
  skip_if_no_session()
  session <- SecureSession$new()
  priv <- session$.__enclos_env__$private
  socket_dir <- priv$socket_dir
  expect_true(dir.exists(socket_dir))

  session$close()
  expect_false(dir.exists(socket_dir))
})

test_that("socket directory is cleaned up on timeout", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  old_socket_dir <- priv$socket_dir
  expect_true(dir.exists(old_socket_dir))

  # Trigger a timeout — this kills the process and restarts
  expect_error(
    session$execute("while(TRUE) {}", timeout = 1),
    "timed out"
  )

  # The old socket dir should have been cleaned up
  expect_false(dir.exists(old_socket_dir))

  # A new socket dir should now exist (from the restart)
  new_socket_dir <- priv$socket_dir
  expect_true(dir.exists(new_socket_dir))
  expect_false(identical(old_socket_dir, new_socket_dir))
})

# --- IPC authentication tests (Finding 9) ---

test_that("session generates and stores an IPC token", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  token <- priv$ipc_token

  expect_true(is.character(token))
  expect_equal(length(token), 1)
  expect_true(nchar(token) %in% c(32, 64))
  expect_true(grepl("^[A-Za-z0-9]+$", token))
})

test_that("child used the token for auth (env var is cleared after)", {
  skip_if_no_session()
  session <- SecureSession$new()
  on.exit(session$close())

  # The session is alive and functional, which means the token was
  # successfully sent to the parent during child startup.
  # After auth, the env var is cleared for security.
  result <- session$execute("Sys.getenv('SECURER_TOKEN')")
  expect_equal(result, "")

  # Session still works, proving auth succeeded
  expect_equal(session$execute("1 + 1"), 2)
})

# --- Low-level IPC helper timeout/error tests ---

test_that("ipc_accept() errors on timeout when no client connects", {
  skip_if_no_session()
  socket_path <- file.path("/tmp", paste0("securer_test_accept_", Sys.getpid(), ".sock"))
  on.exit(unlink(socket_path), add = TRUE)

  server <- processx::conn_create_unix_socket(socket_path)

  # No client connects — should timeout
  expect_error(
    ipc_accept(server, timeout = 100L),
    "Timeout waiting for client connection"
  )
})

test_that("ipc_read_message() errors on timeout when no data sent", {
  skip_if_no_session()
  socket_path <- file.path("/tmp", paste0("securer_test_read_", Sys.getpid(), ".sock"))
  on.exit(unlink(socket_path), add = TRUE)

  server <- processx::conn_create_unix_socket(socket_path)
  client <- processx::conn_connect_unix_socket(socket_path)

  # Accept the connection (transitions server in-place)
  ipc_accept(server, timeout = 1000L)

  # No data sent — should timeout
  expect_error(
    ipc_read_message(server, timeout = 100L),
    "Timeout waiting for IPC message"
  )
})

test_that("ipc_read_message() errors on empty message (closed connection)", {
  skip_if_no_session()
  socket_path <- file.path("/tmp", paste0("securer_test_empty_", Sys.getpid(), ".sock"))
  on.exit(unlink(socket_path), add = TRUE)

  server <- processx::conn_create_unix_socket(socket_path)
  client <- processx::conn_connect_unix_socket(socket_path)

  # Accept the connection
  ipc_accept(server, timeout = 1000L)

  # Close the client end so server gets EOF
  close(client)

  # Brief pause to let the close propagate
  Sys.sleep(0.1)

  # Reading should get an empty message or timeout — either is an error
  expect_error(
    ipc_read_message(server, timeout = 1000L),
    "Empty message received|Timeout waiting for IPC message"
  )
})

test_that("each session gets a unique token", {
  skip_if_no_session()
  s1 <- SecureSession$new()
  s2 <- SecureSession$new()
  on.exit({ s1$close(); s2$close() })

  t1 <- s1$.__enclos_env__$private$ipc_token
  t2 <- s2$.__enclos_env__$private$ipc_token
  expect_false(identical(t1, t2))
})
