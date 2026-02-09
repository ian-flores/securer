test_that("Tool call pause/resume works", {
  add_fn <- function(a, b) a + b

  session <- SecureSession$new(tools = list(add = add_fn))
  on.exit(session$close())

  result <- session$execute(".securer_call_tool('add', a = 2, b = 3)")
  expect_equal(result, 5)
})

test_that("Multiple tool calls in sequence work", {
  add_fn <- function(a, b) a + b

  session <- SecureSession$new(tools = list(add = add_fn))
  on.exit(session$close())

  result <- session$execute("
    x <- .securer_call_tool('add', a = 1, b = 2)
    y <- .securer_call_tool('add', a = x, b = 10)
    y
  ")
  expect_equal(result, 13)
})

test_that("Unknown tool call returns error", {
  session <- SecureSession$new(tools = list())
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool('nonexistent', x = 1)"),
    "Unknown tool"
  )
})

test_that("Tool execution error is propagated", {
  bad_fn <- function() stop("tool failed")

  session <- SecureSession$new(tools = list(bad = bad_fn))
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool('bad')"),
    "tool failed"
  )
})

test_that("Overwriting .securer_call_tool in child is prevented", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute(".securer_call_tool <- function(...) 'hijacked'"),
    "cannot change value of locked binding"
  )
})

test_that("Overwriting .securer_connect in child is prevented", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute(".securer_connect <- function() 'hijacked'"),
    "cannot change value of locked binding"
  )
})

test_that("Overwriting .securer_env in child is prevented", {
  session <- SecureSession$new()
  on.exit(session$close())

  expect_error(
    session$execute(".securer_env <- new.env()"),
    "cannot change value of locked binding"
  )
})

test_that("Tool calls still work after bindings are locked", {
  add_fn <- function(a, b) a + b

  session <- SecureSession$new(tools = list(add = add_fn))
  on.exit(session$close())

  result <- session$execute(".securer_call_tool('add', a = 10, b = 20)")
  expect_equal(result, 30)
})

# --- Socket directory isolation tests (Finding 8) ---

test_that("socket lives in a private directory with 0700 permissions", {
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  socket_dir <- priv$socket_dir
  socket_path <- priv$socket_path

  # Socket directory exists and is a directory

  expect_true(dir.exists(socket_dir))

  # Socket path is inside the private directory
  expect_equal(dirname(socket_path), socket_dir)
  expect_equal(basename(socket_path), "ipc.sock")

  # Directory permissions are 0700 (owner only)
  info <- file.info(socket_dir)
  mode <- as.integer(info$mode)
  # 0700 in octal = 448 in decimal
  expect_equal(bitwAnd(mode, 511L), 448L)
})

test_that("socket directory is cleaned up on close", {
  session <- SecureSession$new()
  priv <- session$.__enclos_env__$private
  socket_dir <- priv$socket_dir
  expect_true(dir.exists(socket_dir))

  session$close()
  expect_false(dir.exists(socket_dir))
})

test_that("socket directory is cleaned up on timeout", {
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
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  token <- priv$ipc_token

  expect_true(is.character(token))
  expect_equal(length(token), 1)
  expect_equal(nchar(token), 32)
  expect_true(grepl("^[A-Za-z0-9]+$", token))
})

test_that("child receives the token via env var", {
  session <- SecureSession$new()
  on.exit(session$close())

  priv <- session$.__enclos_env__$private
  expected_token <- priv$ipc_token

  # Ask the child what token it received
  result <- session$execute("Sys.getenv('SECURER_TOKEN')")
  expect_equal(result, expected_token)
})

test_that("each session gets a unique token", {
  s1 <- SecureSession$new()
  s2 <- SecureSession$new()
  on.exit({ s1$close(); s2$close() })

  t1 <- s1$.__enclos_env__$private$ipc_token
  t2 <- s2$.__enclos_env__$private$ipc_token
  expect_false(identical(t1, t2))
})
