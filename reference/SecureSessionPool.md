# SecureSessionPool

R6 class for a pool of pre-warmed
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
instances.

Creates multiple sessions at initialization time so that `$execute()`
calls can run immediately on an idle session without waiting for process
startup. Sessions are returned to the pool after each execution
completes (or errors).

## Value

An R6 object of class `SecureSessionPool`.

## Thread Safety

`SecureSessionPool` is **NOT** thread-safe. The acquire/release
mechanism uses no locking and assumes single-threaded access. If you
need to use pools from multiple processes (e.g., via
[`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html) or
`future`), each process should create its own pool instance. Sharing a
single pool across threads or forked processes will lead to race
conditions in session acquisition.

## Methods

### Public methods

- [`SecureSessionPool$new()`](#method-SecureSessionPool-new)

- [`SecureSessionPool$execute()`](#method-SecureSessionPool-execute)

- [`SecureSessionPool$size()`](#method-SecureSessionPool-size)

- [`SecureSessionPool$available()`](#method-SecureSessionPool-available)

- [`SecureSessionPool$status()`](#method-SecureSessionPool-status)

- [`SecureSessionPool$format()`](#method-SecureSessionPool-format)

- [`SecureSessionPool$print()`](#method-SecureSessionPool-print)

- [`SecureSessionPool$close()`](#method-SecureSessionPool-close)

------------------------------------------------------------------------

### Method `new()`

Create a new SecureSessionPool

#### Usage

    SecureSessionPool$new(
      size = 4L,
      tools = list(),
      sandbox = TRUE,
      limits = NULL,
      verbose = FALSE,
      reset_between_uses = FALSE
    )

#### Arguments

- `size`:

  Integer, number of sessions to pre-warm (default 4, minimum 1).

- `tools`:

  A list of
  [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  objects passed to each session.

- `sandbox`:

  Logical, whether to enable OS-level sandboxing.

- `limits`:

  Optional named list of resource limits.

- `verbose`:

  Logical, whether to emit diagnostic messages.

- `reset_between_uses`:

  Logical, whether to restart each session after an execution before
  returning it to the pool (default `FALSE`). When `TRUE`, calls
  `session$restart()` after every `$execute()` to prevent state leaking
  between executions (e.g., variables, loaded packages, options set by
  prior code).

------------------------------------------------------------------------

### Method `execute()`

Execute R code on an available pooled session

#### Usage

    SecureSessionPool$execute(code, timeout = NULL, acquire_timeout = NULL)

#### Arguments

- `code`:

  Character string of R code to execute.

- `timeout`:

  Timeout in seconds, or `NULL` for no timeout.

- `acquire_timeout`:

  Optional timeout in seconds to wait for a session to become available.
  If `NULL` (default), fails immediately when all sessions are busy. If
  provided, retries acquisition with a short sleep (0.1s) between
  retries until the timeout expires.

#### Returns

The result of evaluating the code.

------------------------------------------------------------------------

### Method `size()`

Number of sessions in the pool

#### Usage

    SecureSessionPool$size()

#### Returns

Integer

------------------------------------------------------------------------

### Method `available()`

Number of idle (non-busy) sessions

#### Usage

    SecureSessionPool$available()

#### Returns

Integer

------------------------------------------------------------------------

### Method `status()`

Summary of pool state

#### Usage

    SecureSessionPool$status()

#### Returns

A named list with `total`, `busy`, `idle`, and `dead` counts. `dead`
indicates sessions that have crashed and need restart.

------------------------------------------------------------------------

### Method [`format()`](https://rdrr.io/r/base/format.html)

Format method for display

#### Usage

    SecureSessionPool$format(...)

#### Arguments

- `...`:

  Ignored.

#### Returns

A character string describing the pool.

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print method

#### Usage

    SecureSessionPool$print(...)

#### Arguments

- `...`:

  Ignored.

#### Returns

Invisible self.

------------------------------------------------------------------------

### Method [`close()`](https://rdrr.io/r/base/connections.html)

Close all sessions and shut down the pool

#### Usage

    SecureSessionPool$close()

#### Returns

Invisible self

## Examples

``` r
# \donttest{
pool <- SecureSessionPool$new(size = 2, sandbox = FALSE)
pool$execute("1 + 1")
#> [1] 2
pool$execute("2 + 2")
#> [1] 4
pool$close()
# }
```
