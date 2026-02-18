# Integration Examples

These examples show how to embed securer in common R application
frameworks. Each example is self-contained and can be adapted to your
own project. All code chunks use `eval = FALSE` — copy them into your
application and adjust as needed.

## Shiny

A minimal Shiny app that lets users type R code and execute it inside a
sandboxed session. The `SecureSession` is created once when the Shiny
session starts and closed when the user disconnects.

``` r
library(shiny)
library(securer)

ui <- fluidPage(
  titlePanel("Secure R Executor"),
  sidebarLayout(
    sidebarPanel(
      textAreaInput(
        "code", "R Code",
        value = "1 + 1",
        rows = 8
      ),
      actionButton("run", "Run Code")
    ),
    mainPanel(
      verbatimTextOutput("result")
    )
  )
)

server <- function(input, output, session) {
  # One SecureSession per Shiny session

  secure <- SecureSession$new(sandbox = TRUE)

  # Clean up when the user disconnects
  session$onSessionEnded(function() {
    secure$close()
  })

  result_val <- reactiveVal("Enter code and click Run.")

  observeEvent(input$run, {
    result_val(
      tryCatch(
        {
          res <- secure$execute(input$code, timeout = 10)
          paste(capture.output(print(res)), collapse = "\n")
        },
        error = function(e) paste("Error:", conditionMessage(e))
      )
    )
  })

  output$result <- renderText(result_val())
}

shinyApp(ui, server)
```

For multi-user apps that handle many concurrent visitors, consider using
`SecureSessionPool` instead of creating one `SecureSession` per Shiny
session. A single pool can be shared across all Shiny sessions — each
request acquires an idle session, executes, and returns it to the pool
automatically.

## Plumber API

A REST API that accepts R code via POST and executes it in a sandboxed
pool. The pool is created once at startup and shared across all
requests.

``` r
# plumber.R
library(plumber)
library(securer)

# Create the pool at startup -- sessions are pre-warmed and reused.
# reset_between_uses = TRUE restarts each session after use so that
# variables and packages from one request do not leak into the next.
pool <- SecureSessionPool$new(
  size = 4,
  sandbox = TRUE,
  reset_between_uses = TRUE
)
```

``` r
#* Execute R code in a sandboxed session
#* @param code Character string of R code
#* @post /execute
function(req, res, code = "") {
  if (nchar(code) == 0) {
    res$status <- 400
    return(list(error = "Missing 'code' parameter"))
  }

  tryCatch(
    {
      result <- pool$execute(code, timeout = 10)
      list(result = result)
    },
    error = function(e) {
      res$status <- 500
      list(error = conditionMessage(e))
    }
  )
}
```

``` r
# Start the API
pr <- plumb("plumber.R")
pr$run(host = "0.0.0.0", port = 8080)
```

**API hardening tips:**

- Validate `nchar(code)` before execution to reject oversized payloads —
  `SecureSession$execute()` enforces `max_code_length` (default 100 000
  characters) but an early check avoids unnecessary work.
- Set `timeout` to a value appropriate for your workload. The sandbox
  enforces CPU-time limits via `ulimit`, but `timeout` catches
  wall-clock delays from I/O waits.
- Use `max_tool_calls` on individual `session$execute()` calls if tools
  are registered, to cap iterations.
- Enable `sanitize_errors = TRUE` on the underlying sessions if error
  messages are returned to untrusted clients — this strips file paths
  and PIDs.

## Batch Processing

Processing a vector of code snippets in parallel using a session pool.
The pool manages a fixed number of sessions — `lapply` iterates
sequentially but each execution reuses a pre-warmed process, avoiding
repeated startup costs.

``` r
library(securer)

# Code snippets to evaluate
snippets <- c(
  "mean(1:100)",
  "sqrt(144)",
  "UNDEFINED_VAR + 1",       # will error
  "paste('hello', 'world')",
  "sum(rnorm(1000))"
)
```

``` r
pool <- SecureSessionPool$new(size = 2, sandbox = TRUE)

results <- lapply(snippets, function(code) {
  tryCatch(
    {
      value <- pool$execute(code, timeout = 5)
      list(code = code, result = value, error = NA_character_)
    },
    error = function(e) {
      list(code = code, result = NA, error = conditionMessage(e))
    }
  )
})

pool$close()
```

``` r
# Collect into a data frame for inspection
outcome <- data.frame(
  code  = vapply(results, `[[`, character(1), "code"),
  error = vapply(results, `[[`, character(1), "error"),
  stringsAsFactors = FALSE
)
outcome$result <- lapply(results, `[[`, "result")

outcome[, c("code", "error")]
#>                        code                             error
#> 1             mean(1:100)                               <NA>
#> 2               sqrt(144)                               <NA>
#> 3     UNDEFINED_VAR + 1    object 'UNDEFINED_VAR' not found
#> 4  paste('hello', 'world')                              <NA>
#> 5       sum(rnorm(1000))                               <NA>
```

Successful results are stored in the `result` column as a list. Errors
are captured per-snippet so that one failure does not abort the entire
batch. For larger workloads, increase the `size` argument to
`SecureSessionPool$new()` to allow more sessions to run concurrently —
keeping in mind that each session is a separate R process.
