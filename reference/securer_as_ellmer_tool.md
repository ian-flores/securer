# Create an ellmer tool for secure R code execution

Wraps a
[SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
as an
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definition so an LLM can execute R code in a sandboxed environment. The
tool accepts a single `code` argument (a string of R code) and returns
the result.

## Usage

``` r
securer_as_ellmer_tool(
  session = NULL,
  tools = list(),
  sandbox = TRUE,
  limits = NULL,
  timeout = 30
)
```

## Arguments

- session:

  A
  [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
  object. If `NULL` (the default), a new session is created with the
  given `tools`, `sandbox`, and `limits` arguments. When you supply your
  own session, those arguments are ignored.

- tools:

  A list of
  [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  objects to register in the session. Only used when `session` is
  `NULL`.

- sandbox:

  Logical, whether to enable OS-level sandboxing. Only used when
  `session` is `NULL`. Defaults to `TRUE`.

- limits:

  Optional named list of resource limits. Only used when `session` is
  `NULL`.

- timeout:

  Timeout in seconds for each code execution, or `NULL` for no timeout.
  Defaults to 30.

## Value

An ellmer `ToolDef` object that can be registered with
`chat$register_tool()`.

## Examples

``` r
if (FALSE) { # \dontrun{
library(ellmer)

# Basic usage: LLM can execute R code in a sandbox
chat <- chat_openai()
chat$register_tool(securer_as_ellmer_tool())
chat$chat("What is the mean of the numbers 1 through 100?")

# With custom tools available inside the sandbox
tools <- list(
  securer_tool("fetch_data", "Fetch a dataset by name",
    fn = function(name) get(name, "package:datasets"),
    args = list(name = "character"))
)
chat$register_tool(securer_as_ellmer_tool(tools = tools))
chat$chat("Load the mtcars dataset and compute the mean mpg.")

# With a pre-existing session
session <- SecureSession$new(sandbox = TRUE)
chat$register_tool(securer_as_ellmer_tool(session = session))
# ... use chat ...
session$close()
} # }
```
