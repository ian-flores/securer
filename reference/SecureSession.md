# SecureSession

R6 class for secure code execution with tool-call IPC.

Wraps a
[`callr::r_session`](https://callr.r-lib.org/reference/r_session.html)
with a bidirectional Unix domain socket protocol that allows code
running in the child process to pause, call tools on the parent side,
and resume with the result.

## Methods

### Public methods

- [`SecureSession$new()`](#method-SecureSession-new)

- [`SecureSession$execute()`](#method-SecureSession-execute)

- [`SecureSession$close()`](#method-SecureSession-close)

- [`SecureSession$is_alive()`](#method-SecureSession-is_alive)

- [`SecureSession$clone()`](#method-SecureSession-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new SecureSession

#### Usage

    SecureSession$new(
      tools = list(),
      sandbox = FALSE,
      limits = NULL,
      verbose = FALSE,
      audit_log = NULL
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
  bubblewrap (`bwrap`) with full namespace isolation. On Windows,
  `sandbox = TRUE` raises an error because OS-level isolation is not
  available; use `sandbox = FALSE` with explicit limits, or run inside a
  container. On other platforms the session runs without sandboxing.

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

- `audit_log`:

  Optional path to a JSONL file for persistent audit logging. If `NULL`
  (the default), no file logging is performed. When a path is provided,
  structured JSON entries are appended for session lifecycle events,
  executions, and tool calls.

------------------------------------------------------------------------

### Method `execute()`

Execute R code in the secure session

#### Usage

    SecureSession$execute(
      code,
      timeout = NULL,
      validate = TRUE,
      output_handler = NULL,
      max_tool_calls = NULL
    )

#### Arguments

- `code`:

  Character string of R code to execute

- `timeout`:

  Timeout in seconds, or `NULL` for no timeout (default `NULL`)

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

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    SecureSession$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
if (FALSE) { # \dontrun{
# Basic usage
session <- SecureSession$new()
session$execute("1 + 1")
session$close()

# With tools
tools <- list(
  securer_tool("add", "Add numbers",
    fn = function(a, b) a + b,
    args = list(a = "numeric", b = "numeric"))
)
session <- SecureSession$new(tools = tools)
session$execute("add(2, 3)")
session$close()

# With macOS sandbox
session <- SecureSession$new(sandbox = TRUE)
session$execute("1 + 1")
session$close()
} # }
```
