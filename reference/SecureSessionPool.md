# SecureSessionPool

An R6 class for a pool of
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
objects that are started ahead of time.

The pool starts all its sessions when you create it, so `$execute()` can
use an idle one straight away instead of waiting for R to start. Each
session goes back to the pool when its run finishes, whether it
succeeded or failed.

## Value

An R6 object of class `SecureSessionPool`.

## Threads and forks

`SecureSessionPool` isn't thread-safe. Handing out and taking back
sessions uses no locks. If you use pools from several processes (for
example with
[`parallel::mclapply`](https://rdrr.io/r/parallel/mclapply.html) or
`future`), create a pool in each process. Two processes sharing one pool
can end up grabbing the same session.

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

Start a new SecureSessionPool

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

  Integer, number of sessions to start (default 4, minimum 1).

- `tools`:

  A list of
  [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  objects passed to each session.

- `sandbox`:

  Logical, whether to use the OS sandbox.

- `limits`:

  Optional named list of resource limits.

- `verbose`:

  Logical, whether to print what each session is doing.

- `reset_between_uses`:

  Logical, whether to restart each session before it goes back to the
  pool (default `FALSE`). With `TRUE`, the pool calls
  `session$restart()` after every `$execute()`, so variables, loaded
  packages, and options from one run don't carry over to the next.

------------------------------------------------------------------------

### Method `execute()`

Run R code on an idle session from the pool

#### Usage

    SecureSessionPool$execute(code, timeout = NULL, acquire_timeout = NULL)

#### Arguments

- `code`:

  Character string of R code to execute.

- `timeout`:

  Timeout in seconds, or `NULL` for no timeout.

- `acquire_timeout`:

  Optional number of seconds to wait for a free session. If `NULL` (the
  default), the call fails straight away when every session is busy.
  Otherwise the pool keeps trying, every 0.1 seconds, until the time is
  up.

#### Returns

The value of the last expression in `code`.

------------------------------------------------------------------------

### Method `size()`

Number of sessions in the pool

#### Usage

    SecureSessionPool$size()

#### Returns

Integer

------------------------------------------------------------------------

### Method `available()`

Number of idle sessions

#### Usage

    SecureSessionPool$available()

#### Returns

Integer

------------------------------------------------------------------------

### Method `status()`

Count sessions by state

#### Usage

    SecureSessionPool$status()

#### Returns

A named list with `total`, `busy`, `idle`, and `dead` counts. `dead`
counts sessions whose process has stopped and that need a restart.

------------------------------------------------------------------------

### Method [`format()`](https://rdrr.io/r/base/format.html)

Format the pool for printing

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

Close every session in the pool

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
