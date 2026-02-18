# Quick Start

## Overview

securer runs R code in a sandboxed child process with OS-level
isolation. Code in the child can call named “tools” — host-side
functions that execute outside the sandbox. Communication happens over a
Unix domain socket using JSON messages. The package is designed for LLM
agent systems where generated code needs access to host-provided
capabilities while being prevented from reaching the network or
filesystem.

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

The simplest way to run code is with
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md).
It creates a session, runs the code, and tears everything down
automatically:

``` r
library(securer)

execute_r("1 + 1")
#> [1] 2

execute_r("paste('Hello from', R.version.string)")
#> [1] "Hello from R version 4.4.2 (2024-10-31)"
```

By default
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
enables the OS sandbox (`sandbox = TRUE`). Pass `sandbox = FALSE` to
disable it.

## Defining tools

Tools let sandboxed code call functions on the host. Define them with
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

Each tool has four components:

- **name** – the function name available in the child process
- **description** – metadata (useful for LLM tool-use prompts)
- **fn** – the implementation, which runs on the host side
- **args** – argument names mapped to type strings for validation

### Supported type annotations

| Type string    | Check function                                                 |
|----------------|----------------------------------------------------------------|
| `"numeric"`    | [`is.numeric()`](https://rdrr.io/r/base/numeric.html)          |
| `"character"`  | [`is.character()`](https://rdrr.io/r/base/character.html)      |
| `"logical"`    | [`is.logical()`](https://rdrr.io/r/base/logical.html)          |
| `"integer"`    | [`is.integer()`](https://rdrr.io/r/base/integer.html)          |
| `"list"`       | [`is.list()`](https://rdrr.io/r/base/list.html)                |
| `"data.frame"` | [`is.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) |

Type annotations are optional. Arguments without type annotations skip
validation.

## Using tools

Pass tools as a list to
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

Now that you’ve seen the basics:

- [`vignette("sessions-and-tools")`](https://ian-flores.github.io/securer/articles/sessions-and-tools.md)
  — persistent sessions and advanced features
- [`vignette("deployment")`](https://ian-flores.github.io/securer/articles/deployment.md)
  — sandboxing and resource limits
- [`vignette("security-model")`](https://ian-flores.github.io/securer/articles/security-model.md)
  — the full threat model
