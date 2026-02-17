# SecureSession

R6 class for secure code execution with tool-call IPC.

Wraps a
[`callr::r_session`](https://callr.r-lib.org/reference/r_session.html)
with a bidirectional Unix domain socket protocol that allows code
running in the child process to pause, call tools on the parent side,
and resume with the result.

## Value

An R6 object of class `SecureSession`.

## Methods

### Public methods

- [`SecureSession$new()`](#method-SecureSession-new)

- [`SecureSession$execute()`](#method-SecureSession-execute)

- [`SecureSession$close()`](#method-SecureSession-close)

- [`SecureSession$is_alive()`](#method-SecureSession-is_alive)

- [`SecureSession$format()`](#method-SecureSession-format)

- [`SecureSession$print()`](#method-SecureSession-print)

- [`SecureSession$tools()`](#method-SecureSession-tools)

- [`SecureSession$restart()`](#method-SecureSession-restart)

------------------------------------------------------------------------

### Method `new()`

Create a new SecureSession

#### Usage

    SecureSession$new(
      tools = list(),
      sandbox = FALSE,
      limits = NULL,
      verbose = FALSE,
      sandbox_strict = FALSE,
      audit_log = NULL,
      max_executions = NULL,
      pre_execute_hook = NULL,
      sanitize_errors = FALSE
    )

#### Arguments

- `tools`:

  A list of
  [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  objects, or a named list of functions (legacy format for backward
  compatibility)

- `sandbox`:

  Logical, whether to enable the OS-level sandbox. On macOS this uses
  `sandbox-exec` with a Seatbelt profile that denies network access and
  restricts file writes to temp directories. On Linux this uses
  bubblewrap (`bwrap`) with full namespace isolation. On Windows this
  provides environment isolation (clean HOME/TMPDIR, empty R_LIBS_USER)
  and resource limits (memory, CPU time, process count) via Job Objects.
  On other platforms the session runs without sandboxing.

- `limits`:

  An optional named list of resource limits to apply to the child
  process via `ulimit`. Supported names: `cpu` (seconds), `memory`
  (bytes, virtual address space), `fsize` (bytes, max file size),
  `nproc` (max processes), `nofile` (max open files), `stack` (bytes,
  stack size). When `sandbox = TRUE` and `limits` is `NULL` (the
  default), sensible defaults are applied automatically (see
  [`default_limits()`](https://ian-flores.github.io/securer/reference/default_limits.md)).
  Pass `limits = list()` to explicitly disable resource limits. When
  `sandbox = FALSE`, `NULL` means no limits.

- `verbose`:

  Logical, whether to emit diagnostic messages via
  [`message()`](https://rdrr.io/r/base/message.html). Useful for
  debugging. Users can suppress with
  [`suppressMessages()`](https://rdrr.io/r/base/message.html).

- `sandbox_strict`:

  Logical, whether to error if sandbox tools are not available on the
  current platform (default `FALSE`). When `TRUE` and `sandbox = TRUE`,
  the session will stop with an informative error if the OS-level
  sandbox cannot be set up. When `FALSE` (default), the existing
  behavior is preserved: a warning is emitted and the session continues
  without sandboxing.

- `audit_log`:

  Optional path to a JSONL file for persistent audit logging. If `NULL`
  (the default), no file logging is performed. When a path is provided,
  structured JSON entries are appended for session lifecycle events,
  executions, and tool calls.

- `max_executions`:

  Optional integer, the maximum number of `$execute()` calls allowed on
  this session (default `NULL` = unlimited). Once the limit is reached,
  subsequent `$execute()` calls stop with an error. Useful for
  disposable sessions in agent workflows.

- `pre_execute_hook`:

  Optional function taking a single `code` argument. Called at the start
  of every `$execute()` invocation. If it returns `FALSE`, execution is
  blocked with an error. Any other return value (including `NULL` or
  `TRUE`) allows execution to proceed. Default `NULL` (no hook).

- `sanitize_errors`:

  Logical, whether to strip sensitive details (file paths, PIDs,
  hostnames) from error messages returned by `$execute()` (default
  `FALSE`). When `TRUE`,
  [`sanitize_error_message()`](https://ian-flores.github.io/securer/reference/sanitize_error_message.md)
  is applied before the error is raised.

------------------------------------------------------------------------

### Method `execute()`

Execute R code in the secure session

#### Usage

    SecureSession$execute(
      code,
      timeout = 30,
      validate = TRUE,
      output_handler = NULL,
      max_tool_calls = NULL,
      max_code_length = 100000L,
      max_output_lines = NULL
    )

#### Arguments

- `code`:

  Character string of R code to execute

- `timeout`:

  Timeout in seconds (default 30). Pass `NULL` to disable the timeout
  entirely. Both this method and the
  [`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
  convenience wrapper default to 30 seconds. For long-running workloads,
  pass an explicit higher value or `NULL`.

- `validate`:

  Logical, whether to pre-validate the code for syntax errors before
  sending it to the child process (default `TRUE`).

- `output_handler`:

  An optional callback function that receives output lines (character)
  as they arrive from the child process. If `NULL` (default), output is
  only collected and returned as the `"output"` attribute on the result.

- `max_tool_calls`:

  Maximum number of tool calls allowed in this execution, or `NULL` for
  unlimited (default `NULL`).

- `max_code_length`:

  Maximum allowed `nchar(code)` (default 100000). Code exceeding this
  limit is rejected before parsing. Prevents resource exhaustion from
  extremely large code strings.

- `max_output_lines`:

  Maximum number of output lines to accumulate (default `NULL` =
  unlimited). Once the limit is reached, further output from the child
  is still drained but not stored.

#### Returns

The result of evaluating the code, with an `"output"` attribute
containing all captured stdout/stderr as a character vector.

------------------------------------------------------------------------

### Method [`close()`](https://rdrr.io/r/base/connections.html)

Close the session and clean up resources

#### Usage

    SecureSession$close()

#### Returns

Invisible self

------------------------------------------------------------------------

### Method `is_alive()`

Check if session is alive

#### Usage

    SecureSession$is_alive()

#### Returns

Logical

------------------------------------------------------------------------

### Method [`format()`](https://rdrr.io/r/base/format.html)

Format method for display

#### Usage

    SecureSession$format(...)

#### Arguments

- `...`:

  Ignored.

#### Returns

A character string describing the session.

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print method

#### Usage

    SecureSession$print(...)

#### Arguments

- `...`:

  Ignored.

#### Returns

Invisible self.

------------------------------------------------------------------------

### Method `tools()`

List registered tools and their argument specs

#### Usage

    SecureSession$tools()

#### Returns

A named list of tool information. Each element contains `name` and
`args` fields. Returns an empty list if no tools are registered.

------------------------------------------------------------------------

### Method `restart()`

Restart the child R process

Kills the current child process, cleans up the socket, and starts a
fresh child with the runtime and tool wrappers re-injected. The session
remains usable for subsequent `$execute()` calls.

#### Usage

    SecureSession$restart()

#### Returns

Invisible self.

## Examples

``` r
# \donttest{
# Basic usage
session <- SecureSession$new()
session$execute("1 + 1")
#> [1] 2
session$close()

# With tools
tools <- list(
  securer_tool("add", "Add numbers",
    fn = function(a, b) a + b,
    args = list(a = "numeric", b = "numeric"))
)
session <- SecureSession$new(tools = tools)
session$execute("add(2, 3)")
#> [1] 5
session$close()
# }
if (FALSE) { # \dontrun{
# With sandbox (requires platform-specific tools)
session <- SecureSession$new(sandbox = TRUE)
session$execute("1 + 1")
session$close()
} # }
```
