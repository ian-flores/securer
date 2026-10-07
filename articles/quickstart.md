# Quick start

## What securer does

securer runs R code in a separate R process that the operating system
keeps in a sandbox. That code can call “tools”, which are functions you
define. The tools run in your own R session, outside the sandbox, and
the two processes pass messages over a Unix domain socket.

It’s built for LLM agents. The model writes R code, and the code can use
the tools you give it, but it can’t reach the network or your files on
its own.

## Installation

``` r

pak::pak("ian-flores/securer")
```

Verify the installation:

``` r

library(securer)
execute_r("1 + 1")
#> [1] 2
```

## Hello world

The simplest way to run code is
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md).
It starts a session, runs the code, and shuts the session down again:

``` r

library(securer)

execute_r("1 + 1")
#> [1] 2

execute_r("paste('Hello from', R.version.string)")
#> [1] "Hello from R version 4.4.2 (2024-10-31)"
```

[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
uses the sandbox by default (`sandbox = TRUE`). Pass `sandbox = FALSE`
to turn it off.

## Defining tools

A tool is a function that sandboxed code can call but that runs in your
session. Make one with
[`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md):

``` r

add_tool <- securer_tool(
  name = "add",
  description = "Add two numbers",
  fn = function(a, b) a + b,
  args = list(a = "numeric", b = "numeric")
)
add_tool
```

A tool has a `name`, which is what the sandboxed code calls it, and a
`description`, which you can show to an LLM so it knows what the tool is
for. `fn` is the function that actually runs, in your session. `args`
lists the argument names and, optionally, the type each one must have.

### Argument types

| Type string | Check function |
|----|----|
| `"numeric"` | [`is.numeric()`](https://rdrr.io/r/base/numeric.html) |
| `"character"` | [`is.character()`](https://rdrr.io/r/base/character.html) |
| `"logical"` | [`is.logical()`](https://rdrr.io/r/base/logical.html) |
| `"integer"` | [`is.integer()`](https://rdrr.io/r/base/integer.html) |
| `"list"` | [`is.list()`](https://rdrr.io/r/base/list.html) |
| `"data.frame"` | [`is.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) |

If you leave out an argument’s type, securer doesn’t check it.

## Using tools

Pass a list of tools to
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md):

``` r

tools <- list(
  securer_tool("add", "Add two numbers",
    fn = function(a, b) a + b,
    args = list(a = "numeric", b = "numeric")),
  securer_tool("get_weather", "Get weather for a city",
    fn = function(city) list(temp = 72, condition = "sunny"),
    args = list(city = "character"))
)

execute_r('add(2, 3)', tools = tools)
#> [1] 5

execute_r('get_weather("Boston")', tools = tools)
#> $temp
#> [1] 72
#>
#> $condition
#> [1] "sunny"
```

## Next steps

- [`vignette("sessions-and-tools")`](https://ian-flores.github.io/securer/articles/sessions-and-tools.md)
  covers sessions you keep open, streaming output, and pools.
- [`vignette("deployment")`](https://ian-flores.github.io/securer/articles/deployment.md)
  covers the sandboxes and resource limits.
- [`vignette("security-model")`](https://ian-flores.github.io/securer/articles/security-model.md)
  covers what securer protects against, and what it doesn’t.
