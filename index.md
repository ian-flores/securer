# securer

securer runs R code written by an LLM in a sandbox, and lets that code
call functions you choose. The calls run in your own R session, so the
code can reach your data through those functions and nothing else.

The package is experimental, and function names may still change.

## Installation

``` r

# install.packages("pak")
pak::pak("ian-flores/securer")
```

Check that it works:

``` r

library(securer)
execute_r("1 + 1")
#> [1] 2
```

## A quick look

Give the sandboxed code a function it can call. Here that function is a
stand-in for a database query:

``` r

library(securer)

tools <- list(
  securer_tool("query_db", "Query a database table",
    fn = function(table, limit) head(get(table, "package:datasets"), limit),
    args = list(table = "character", limit = "numeric"))
)

result <- execute_r('
  data <- query_db("mtcars", 5)
  mean(data$mpg)
', tools = tools, sandbox = TRUE)
```

When the code reaches `query_db()`, it pauses. Your session runs the
real function, outside the sandbox, and sends the result back. Then the
code carries on. The LLM’s code never touches your files, network, or
data directly.

## Why use it

LLM-written code can do things you didn’t ask for. securer limits what
it can do:

| Risk | What securer does |
|----|----|
| The code reads or writes your files | An OS sandbox lets it write only to a temp directory and read only R’s own files and libraries |
| The code makes network requests | Network access is blocked, by namespaces on Linux and Seatbelt on macOS |
| The code needs your APIs or databases | You register tool functions, which run in your session |
| The code runs forever | A timeout stops it, and the session restarts so you can keep using it |
| The code uses all your memory | Resource limits, with `ulimit` on Linux and macOS and Job Objects on Windows |
| The code doesn’t parse | It’s checked for syntax errors before it’s sent to the sandbox |

Posit’s commons package has its own sandbox for its built-in agents, but
you can’t reuse it for an agent you write yourself. securer is meant for
that case.

## How it works

![](data:image/svg+xml;base64,PHN2ZyByb2xlPSJpbWciIGFyaWEtbGFiZWw9Ikhvc3Qgc2VuZHMgY29kZSB0byB0aGUgc2FuZGJveGVkIGNoaWxkOyB0aGUgY2hpbGQgcGF1c2VzIG9uIGEgdG9vbCBjYWxsLCB0aGUgaG9zdCBydW5zIGl0LCBzZW5kcyB0aGUgcmVzdWx0IGJhY2ssIGFuZCB0aGUgY2hpbGQgcmV0dXJucyB0aGUgZmluYWwgdmFsdWUiIHZpZXdib3g9IjAgMCA5MDAgMjkyIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxkZWZzPjxtYXJrZXIgaWQ9InRjLWFycm93IiB2aWV3Ym94PSIwIDAgMTAgMTAiIHJlZng9IjkiIHJlZnk9IjUiIG1hcmtlcndpZHRoPSI3IiBtYXJrZXJoZWlnaHQ9IjciIG9yaWVudD0iYXV0by1zdGFydC1yZXZlcnNlIj48cGF0aCBkPSJNMSAxTDkgNUwxIDkiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzJiMWYxMiIgc3Ryb2tlLXdpZHRoPSIxIiAvPjwvbWFya2VyPjxwYXR0ZXJuIGlkPSJ0Yy1oYXRjaCIgd2lkdGg9IjYiIGhlaWdodD0iNiIgcGF0dGVybnVuaXRzPSJ1c2VyU3BhY2VPblVzZSIgcGF0dGVybnRyYW5zZm9ybT0icm90YXRlKDQ1KSI+PGxpbmUgeDE9IjAiIHkxPSIwIiB4Mj0iMCIgeTI9IjYiIHN0cm9rZT0iI2JmNWEzNiIgc3Ryb2tlLXdpZHRoPSIwLjYiIG9wYWNpdHk9IjAuNTUiPjwvbGluZT48L3BhdHRlcm4+PC9kZWZzPjxyZWN0IHg9IjQ0MCIgeT0iMjAiIHdpZHRoPSI0NDAiIGhlaWdodD0iMjU4IiBmaWxsPSJ1cmwoI3RjLWhhdGNoKSIgb3BhY2l0eT0iMC4zNSIgc3Ryb2tlPSJub25lIiAvPjxyZWN0IHg9IjQ0MCIgeT0iMjAiIHdpZHRoPSI0NDAiIGhlaWdodD0iMjU4IiBmaWxsPSJub25lIiBzdHJva2U9IiNiZjVhMzYiIHN0cm9rZS13aWR0aD0iMC43NSIgc3Ryb2tlLWRhc2hhcnJheT0iNCAzIiAvPjx0ZXh0IHg9Ijg3MiIgeT0iMzYiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSI4LjUiIGZpbGw9IiNiZjVhMzYiIHRleHQtYW5jaG9yPSJlbmQiIGZvbnQtd2VpZ2h0PSI0MDAiIGxldHRlci1zcGFjaW5nPSIxLjYiPk9TIFNBTkRCT1g8L3RleHQ+PHJlY3QgeD0iMTQwIiB5PSI0MCIgd2lkdGg9IjE4MCIgaGVpZ2h0PSIzNiIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjMmIxZjEyIiBzdHJva2Utd2lkdGg9IjAuNzUiIC8+PHRleHQgeD0iMjMwLjAiIHk9IjYyLjAiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSIxMC41IiBmaWxsPSIjMmIxZjEyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXdlaWdodD0iNzAwIiBsZXR0ZXItc3BhY2luZz0iMS4yIj5IT1NUIFIgU0VTU0lPTjwvdGV4dD48cmVjdCB4PSI1MDAiIHk9IjQwIiB3aWR0aD0iMTgwIiBoZWlnaHQ9IjM2IiBmaWxsPSJub25lIiBzdHJva2U9IiMyYjFmMTIiIHN0cm9rZS13aWR0aD0iMC43NSIgLz48dGV4dCB4PSI1OTAuMCIgeT0iNjIuMCIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjEwLjUiIGZpbGw9IiMyYjFmMTIiIHRleHQtYW5jaG9yPSJtaWRkbGUiIGZvbnQtd2VpZ2h0PSI3MDAiIGxldHRlci1zcGFjaW5nPSIxLjIiPkNISUxEIFIgUFJPQ0VTUzwvdGV4dD48cGF0aCBkPSJNMjMwIDc2VjI3NE01OTAgNzZWMjc0IiBzdHJva2U9IiM2YjU2MzgiIHN0cm9rZS13aWR0aD0iMC42IiBzdHJva2UtZGFzaGFycmF5PSIxIDMiIC8+PHBhdGggZD0iTTIzMCAxMzJINTg4IiBmaWxsPSJub25lIiBzdHJva2U9IiMyYjFmMTIiIHN0cm9rZS13aWR0aD0iMC43NSIgbWFya2VyLWVuZD0idXJsKCN0Yy1hcnJvdykiIC8+PHRleHQgeD0iNDEwLjAiIHk9IjEyNSIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkuNSIgZmlsbD0iIzJiMWYxMiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuOCI+U0VORCBUSEUgQ09ERTwvdGV4dD48dGV4dCB4PSI2MDQiIHk9IjEzNiIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkiIGZpbGw9IiM2YjU2MzgiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuMyI+cnVucyBpdDwvdGV4dD48cGF0aCBkPSJNNTkwIDE3MkgyMzIiIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzJiMWYxMiIgc3Ryb2tlLXdpZHRoPSIwLjc1IiBtYXJrZXItZW5kPSJ1cmwoI3RjLWFycm93KSIgLz48dGV4dCB4PSI0MTAuMCIgeT0iMTY1IiBmb250LWZhbWlseT0iU3BhY2UgTW9ubywgdWktbW9ub3NwYWNlLCBtb25vc3BhY2UiIGZvbnQtc2l6ZT0iOS41IiBmaWxsPSIjMmIxZjEyIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LXdlaWdodD0iNDAwIiBsZXR0ZXItc3BhY2luZz0iMC44Ij5UT09MIENBTEw8L3RleHQ+PHRleHQgeD0iMjE2IiB5PSIxNzYiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSI5IiBmaWxsPSIjNmI1NjM4IiB0ZXh0LWFuY2hvcj0iZW5kIiBmb250LXdlaWdodD0iNDAwIiBsZXR0ZXItc3BhY2luZz0iMC4zIj5ydW5zIHlvdXIgdG9vbCBmdW5jdGlvbjwvdGV4dD48dGV4dCB4PSI2MDQiIHk9IjE3NiIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkiIGZpbGw9IiM2YjU2MzgiIHRleHQtYW5jaG9yPSJzdGFydCIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuMyI+cGF1c2VzIG9uIHRoZSBzb2NrZXQ8L3RleHQ+PHBhdGggZD0iTTIzMCAyMTJINTg4IiBmaWxsPSJub25lIiBzdHJva2U9IiMyYjFmMTIiIHN0cm9rZS13aWR0aD0iMC43NSIgbWFya2VyLWVuZD0idXJsKCN0Yy1hcnJvdykiIC8+PHRleHQgeD0iNDEwLjAiIHk9IjIwNSIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkuNSIgZmlsbD0iIzJiMWYxMiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuOCI+VE9PTCBSRVNVTFQ8L3RleHQ+PHRleHQgeD0iNjA0IiB5PSIyMTYiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSI5IiBmaWxsPSIjNmI1NjM4IiB0ZXh0LWFuY2hvcj0ic3RhcnQiIGZvbnQtd2VpZ2h0PSI0MDAiIGxldHRlci1zcGFjaW5nPSIwLjMiPmNhcnJpZXMgb248L3RleHQ+PHBhdGggZD0iTTU5MCAyNTJIMjMyIiBmaWxsPSJub25lIiBzdHJva2U9IiMyYjFmMTIiIHN0cm9rZS13aWR0aD0iMC43NSIgbWFya2VyLWVuZD0idXJsKCN0Yy1hcnJvdykiIC8+PHRleHQgeD0iNDEwLjAiIHk9IjI0NSIgZm9udC1mYW1pbHk9IlNwYWNlIE1vbm8sIHVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIiBmb250LXNpemU9IjkuNSIgZmlsbD0iIzJiMWYxMiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZm9udC13ZWlnaHQ9IjQwMCIgbGV0dGVyLXNwYWNpbmc9IjAuOCI+RklOQUwgVkFMVUU8L3RleHQ+PHRleHQgeD0iMjE2IiB5PSIyNTYiIGZvbnQtZmFtaWx5PSJTcGFjZSBNb25vLCB1aS1tb25vc3BhY2UsIG1vbm9zcGFjZSIgZm9udC1zaXplPSI5IiBmaWxsPSIjNmI1NjM4IiB0ZXh0LWFuY2hvcj0iZW5kIiBmb250LXdlaWdodD0iNDAwIiBsZXR0ZXItc3BhY2luZz0iMC4zIj5oYW5kcyBpdCBiYWNrIHRvIHlvdTwvdGV4dD48L3N2Zz4=)

Fig. 1 · A tool call: the code runs in the child, your function runs in
the host

The two processes talk over a Unix domain socket. A tool call blocks the
child until the parent sends back the result.

## Features

### Sessions

Starting a sandboxed R process takes a moment. Keep one open to run
several pieces of code:

``` r

session <- SecureSession$new(tools = tools, sandbox = TRUE)

session$execute('query_db("iris", 3)')
session$execute('query_db("mtcars", 5)')

session$close()
```

### Session pools

If you run many requests at once, start a few sessions ahead of time:

``` r

pool <- SecureSessionPool$new(size = 4, tools = tools, sandbox = TRUE)

result <- pool$execute('query_db("iris", 3)')

pool$close()
```

### Resource limits

Cap CPU time, memory, file size, and more. Limits work on every
platform, with or without the sandbox:

``` r

result <- execute_r("1 + 1",
  limits = list(cpu = 10, memory = 256 * 1024 * 1024)
)
```

### Timeouts

Code that runs too long is stopped. The session restarts itself, so you
can use it again straight away:

``` r

session <- SecureSession$new()
session$execute("Sys.sleep(100)", timeout = 5)
# Error: Execution timed out after 5 seconds
session$execute("1 + 1")  # still works
```

### Syntax checks

Code that doesn’t parse fails right away, without a trip to the child
process:

``` r

session$execute("if (TRUE {")  # immediate error
```

### ellmer

Give an [ellmer](https://ellmer.tidyverse.org/) chat a tool that runs R
code in the sandbox:

``` r

library(ellmer)
chat <- chat_openai()
chat$register_tool(as_ellmer_tool())
chat$chat("Calculate the mean of 1 through 100 using R")
```

### Audit log

Write every session event to a JSONL file, one JSON object per line:

``` r

session <- SecureSession$new(audit_log = "session.jsonl")
```

### Verbose mode

Print what the session is doing as it happens:

``` r

session <- SecureSession$new(tools = tools, verbose = TRUE)
session$execute('query_db("iris", 3)')
# [securer] Session started (sandbox=false, pid=1234)
# [securer] Tool call: query_db(table=iris, limit=3)
# [securer] Tool result: query_db -> ... (0.00s)
# [securer] Execution complete (0.27s)
```

## Platform support

| Platform | Sandbox | Network blocked | Filesystem restricted | Resource limits |
|----|----|----|----|----|
| Linux | bubblewrap (`bwrap`) | Yes | Yes | Yes (`ulimit`) |
| macOS | Seatbelt (`sandbox-exec`) | Yes | Yes | Yes (`ulimit`) |
| Windows | Job Objects and a clean environment | No | No | Yes (memory, CPU, process count) |
| docker-spawn (any host) | A new container per session | Yes (`--network=none`) | Yes (container filesystem) | Yes (`--memory`, `--cpus`, `ulimit`) |

Tool calls, timeouts, and syntax checks work everywhere.

On Windows, securer can only clean the environment and set resource
limits. It can’t stop the code from reading files or using the network.
If you need that on Windows, use the docker-spawn backend or a Linux VM.

The docker-spawn backend is off by default. Turn it on with
`SECURER_SANDBOX_MODE=docker-spawn`. It needs the `docker` command and a
running Docker daemon. `inst/docker/Dockerfile` has a reference image.

## Security

The sandbox is one of several protections. securer also checks that only
the child it started can connect to the socket, limits resources, strips
secrets from the child’s environment, and checks tool arguments. The
security model vignette
([`vignette("security-model", package = "securer")`](https://ian-flores.github.io/securer/articles/security-model.md))
covers what securer protects against and what it doesn’t.

To report a security problem, email the maintainer instead of opening a
public issue.

## Related packages

securer is part of a small set of packages for running LLM agents in R
more safely:

- [secureguard](https://github.com/ian-flores/secureguard) checks
  prompts, generated code, and outputs for things like prompt injection
  and leaked secrets.
- [securetools](https://github.com/ian-flores/securetools) has
  ready-made tools (file access, SQL, web requests) with limits built
  in.
- [securebench](https://github.com/ian-flores/securebench) measures how
  well your guardrails work. It complements
  [vitals](https://vitals.tidyverse.org/).

They build on Posit’s tools rather than replacing them. For tracing, use
[ellmer](https://ellmer.tidyverse.org/)’s OpenTelemetry support through
the [otel](https://otel.r-lib.org/) package. For retrieval (RAG), use
[ragnar](https://github.com/tidyverse/ragnar).

## Learn more

- [`vignette("quickstart", package = "securer")`](https://ian-flores.github.io/securer/articles/quickstart.md):
  installing and first examples
- [`vignette("sessions-and-tools", package = "securer")`](https://ian-flores.github.io/securer/articles/sessions-and-tools.md):
  sessions, streaming output, and pools
- [`vignette("deployment", package = "securer")`](https://ian-flores.github.io/securer/articles/deployment.md):
  sandboxes, resource limits, and how the pieces fit
- [`vignette("security-model", package = "securer")`](https://ian-flores.github.io/securer/articles/security-model.md):
  what securer protects against
- [`vignette("ellmer-integration", package = "securer")`](https://ian-flores.github.io/securer/articles/ellmer-integration.md):
  using securer with ellmer chats
- [`vignette("integration-examples", package = "securer")`](https://ian-flores.github.io/securer/articles/integration-examples.md):
  Shiny, Plumber, and batch jobs
- [`vignette("troubleshooting", package = "securer")`](https://ian-flores.github.io/securer/articles/troubleshooting.md):
  common problems
- [Function reference](https://ian-flores.github.io/securer/reference/)

Found a bug or have an idea? [Open an
issue](https://github.com/ian-flores/securer/issues).

## License

MIT
