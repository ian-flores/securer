test_that("audit_log=NULL produces no file", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = NULL)
  on.exit(session$close(), add = TRUE)

  session$execute("1 + 1")
  session$close()

  expect_false(file.exists(log_path))
})

test_that("audit log file is created when path is provided", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  expect_true(file.exists(log_path))
})

test_that("session_start event is logged", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("session_start" %in% events)
})

test_that("session_close event is logged", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  session$close()

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("session_close" %in% events)
})

test_that("execute events are logged with code", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  session$execute("1 + 1")

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("execute_start" %in% events)
  expect_true("execute_complete" %in% events)

  # Check that execute_start has the code
  start_entry <- entries[[which(events == "execute_start")]]
  expect_equal(start_entry$code, "1 + 1")
})

test_that("execute_error is logged on failure", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  try(session$execute("stop('boom')"), silent = TRUE)

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("execute_error" %in% events)

  err_entry <- entries[[which(events == "execute_error")]]
  expect_true(grepl("boom", err_entry$error))
})

test_that("execute_timeout is logged on timeout", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  try(session$execute("while(TRUE) {}", timeout = 1), silent = TRUE)

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("execute_timeout" %in% events)
})

test_that("tool_call and tool_result events are logged", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  session <- SecureSession$new(tools = tools, audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  session$execute("add(2, 3)")

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("tool_call" %in% events)
  expect_true("tool_result" %in% events)

  # Check tool_call entry has the tool name
  tc_entry <- entries[[which(events == "tool_call")[1]]]
  expect_equal(tc_entry$tool, "add")
})

test_that("all entries are valid JSONL with required fields", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  tools <- list(
    securer_tool("add", "Add", function(a, b) a + b,
                 args = list(a = "numeric", b = "numeric"))
  )
  session <- SecureSession$new(tools = tools, audit_log = log_path)
  session$execute("add(1, 2)")
  session$close()

  lines <- readLines(log_path)
  expect_true(length(lines) > 0)

  # Every line should parse as valid JSON
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)

  for (entry in entries) {
    # Every entry must have timestamp, event, and session_id
    expect_true(!is.null(entry$timestamp), label = "timestamp present")
    expect_true(!is.null(entry$event), label = "event present")
    expect_true(!is.null(entry$session_id), label = "session_id present")

    # timestamp should be ISO8601
    expect_true(
      grepl("^\\d{4}-\\d{2}-\\d{2}T", entry$timestamp),
      label = "timestamp is ISO8601"
    )
  }
})

test_that("session_id is consistent across entries", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  session$execute("1 + 1")
  session$close()

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  session_ids <- vapply(entries, function(e) e$session_id, character(1))

  # All entries should have the same session_id
  expect_true(length(unique(session_ids)) == 1)
})

test_that("execute_r() passes audit_log through", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  execute_r("1 + 1", sandbox = FALSE, audit_log = log_path)

  expect_true(file.exists(log_path))
  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  expect_true("session_start" %in% events)
  expect_true("execute_start" %in% events)
  expect_true("execute_complete" %in% events)
  expect_true("session_close" %in% events)
})


# --- Audit log path validation tests ---

test_that("audit log rejects symlink paths", {
  skip_on_os("windows")

  tmp_dir <- tempfile("audit_symlink_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  real_file <- file.path(tmp_dir, "real.jsonl")
  link_file <- file.path(tmp_dir, "link.jsonl")

  # Create the real file and a symlink to it
  writeLines("", real_file)
  file.symlink(real_file, link_file)

  expect_error(
    SecureSession$new(audit_log = link_file),
    "symlink"
  )
})

test_that("audit log rejects /dev paths", {
  skip_on_os("windows")

  expect_error(
    SecureSession$new(audit_log = "/dev/null"),
    "device file"
  )

  expect_error(
    SecureSession$new(audit_log = "/dev/stderr"),
    "device file"
  )
})

test_that("audit log truncates large code strings in entries", {
  log_path <- tempfile("audit_", fileext = ".jsonl")
  on.exit(unlink(log_path), add = TRUE)

  session <- SecureSession$new(audit_log = log_path)
  on.exit(session$close(), add = TRUE)

  # Create code larger than the 10000 char limit.
  # Use short lines so R's parser doesn't hit its per-line buffer limit.
  big_code <- paste(rep("1", 15000), collapse = "\n")
  try(session$execute(big_code), silent = TRUE)

  lines <- readLines(log_path)
  entries <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  events <- vapply(entries, function(e) e$event, character(1))

  # Find the execute_start entry which should have the code
  start_idx <- which(events == "execute_start")
  expect_true(length(start_idx) > 0)

  start_entry <- entries[[start_idx[1]]]
  # Code should be truncated -- max 10000 chars + "... [truncated]" suffix
  expect_true(nchar(start_entry$code) <= 10000 + nchar("... [truncated]"))
  expect_match(start_entry$code, "\\[truncated\\]")
})

test_that("validate_audit_log_path rejects empty path", {
  expect_error(
    validate_audit_log_path(""),
    "non-empty"
  )
  expect_error(
    validate_audit_log_path(NULL),
    "non-empty"
  )
})

test_that("validate_audit_log_path accepts normal paths", {
  path <- tempfile("audit_valid_", fileext = ".jsonl")
  expect_silent(validate_audit_log_path(path))
})
