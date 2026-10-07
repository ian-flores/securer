# SecureSession

An R6 class for a child R process that runs code, usually in a sandbox,
and can call tools in your session.

It wraps a
[`callr::r_session`](https://callr.r-lib.org/reference/r_session.html)
and connects to it over a Unix domain socket. When code in the child
calls a tool, the child pauses, your session runs the tool, and the
child carries on with the result.

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

Start a new SecureSession

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
  objects, or a named list of functions (the older format, still
  accepted)

- `sandbox`:

  Logical, whether to use the OS sandbox. On macOS this is
  `sandbox-exec` with a Seatbelt profile that blocks the network and
  only allows writes to temp directories. On Linux it's bubblewrap
  (`bwrap`), with the child in its own namespaces. On Windows there's no
  real sandbox: securer cleans the environment (private `HOME` and
  `TMPDIR`, empty `R_LIBS_USER`) and can limit memory, CPU time, and
  process count with a Job Object. On other platforms the session runs
  without a sandbox.

- `limits`:

  An optional named list of resource limits to apply to the child
  process via `ulimit`. Supported names: `cpu` (seconds), `memory`
  (bytes, virtual address space), `fsize` (bytes, max file size),
  `nproc` (max processes), `nofile` (max open files), `stack` (bytes,
  stack size). With `sandbox = TRUE`, `NULL` (the default) means
  [`default_limits()`](https://ian-flores.github.io/securer/reference/default_limits.md),
  and `limits = list()` means no limits. With `sandbox = FALSE`, `NULL`
  means no limits.

- `verbose`:

  Logical, whether to print what the session is doing with
  [`message()`](https://rdrr.io/r/base/message.html). Handy for
  debugging. Use
  [`suppressMessages()`](https://rdrr.io/r/base/message.html) to hide
  them.

- `sandbox_strict`:

  Logical, whether to stop if the sandbox tools aren't available on this
  platform (default `FALSE`). With `TRUE` and `sandbox = TRUE`, the
  session fails to start if it can't set up the sandbox. With `FALSE`,
  you get a warning and the session runs without one.

- `audit_log`:

  Optional path to a JSONL file. If you give one, the session appends a
  JSON line for each start, close, restart, run, and tool call. If
  `NULL` (the default), nothing is written.

- `max_executions`:

  Optional integer, the maximum number of `$execute()` calls this
  session allows. The default, `NULL`, means no limit. After that,
  `$execute()` stops with an error. Useful for throwaway sessions in
  agent code.

- `pre_execute_hook`:

  Optional function taking a single `code` argument, called at the start
  of every `$execute()`. If it returns `FALSE`, the code doesn't run and
  `$execute()` stops with an error. Anything else, `NULL` included, lets
  the code run. The default, `NULL`, means no hook.

- `sanitize_errors`:

  Logical, whether to remove file paths, process IDs, and host names
  from the errors `$execute()` raises (default `FALSE`). With `TRUE`,
  each message goes through
  [`sanitize_error_message()`](https://ian-flores.github.io/securer/reference/sanitize_error_message.md)
  first.

------------------------------------------------------------------------

### Method `execute()`

Run R code in the session

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

  Timeout in seconds (default 30, the same as
  [`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)).
  Pass `NULL` for no timeout. For long jobs, pass a bigger number or
  `NULL`.

- `validate`:

  Logical, whether to check the code for syntax errors before sending it
  to the child process (default `TRUE`).

- `output_handler`:

  Optional function that gets each line of output from the child as it's
  printed. Either way, the output is also attached to the result as its
  `"output"` attribute.

- `max_tool_calls`:

  Maximum number of tool calls allowed in this execution, or `NULL` for
  unlimited (default `NULL`).

- `max_code_length`:

  Largest `nchar(code)` allowed (default 100000). Longer code is
  rejected before it's parsed, so a huge string can't tie up the
  session.

- `max_output_lines`:

  Most lines of output to keep. The default, `NULL`, means no limit.
  Past the limit, securer still reads the child's output but throws it
  away.

#### Returns

The value of the last expression, with an `"output"` attribute holding
the printed stdout and stderr as a character vector.

------------------------------------------------------------------------

### Method [`close()`](https://rdrr.io/r/base/connections.html)

Close the session and remove its temp files

#### Usage

    SecureSession$close()

#### Returns

Invisible self

------------------------------------------------------------------------

### Method `is_alive()`

Check whether the child process is running

#### Usage

    SecureSession$is_alive()

#### Returns

Logical

------------------------------------------------------------------------

### Method [`format()`](https://rdrr.io/r/base/format.html)

Format the session for printing

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

List the registered tools and their arguments

#### Usage

    SecureSession$tools()

#### Returns

A named list of tool information. Each element contains `name` and
`args` fields. Returns an empty list if no tools are registered.

------------------------------------------------------------------------

### Method `restart()`

Restart the child R process

Kills the child process, removes the socket, and starts a new child with
the tools set up again. Variables from before are gone, but you can keep
calling `$execute()`.

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
