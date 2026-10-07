# securer

<!-- badges: start -->
[![R-CMD-check](https://github.com/ian-flores/securer/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ian-flores/securer/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ian-flores/securer/graph/badge.svg)](https://app.codecov.io/gh/ian-flores/securer)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![pkgdown](https://github.com/ian-flores/securer/actions/workflows/pkgdown.yaml/badge.svg)](https://ian-flores.github.io/securer/)
<!-- badges: end -->

securer runs R code written by an LLM in a sandbox, and lets that code call
functions you choose. The calls run in your own R session, so the code can
reach your data through those functions and nothing else.

The package is experimental, and function names may still change.

## Installation

```r
# install.packages("pak")
pak::pak("ian-flores/securer")
```

Check that it works:

```r
library(securer)
execute_r("1 + 1")
#> [1] 2
```

## A quick look

Give the sandboxed code a function it can call. Here that function is a
stand-in for a database query:

```r
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

When the code reaches `query_db()`, it pauses. Your session runs the real
function, outside the sandbox, and sends the result back. Then the code
carries on. The LLM's code never touches your files, network, or data
directly.

## Why use it

LLM-written code can do things you didn't ask for. securer limits what it
can do:

| Risk | What securer does |
|---|---|
| The code reads or writes your files | An OS sandbox lets it write only to a temp directory and read only R's own files and libraries |
| The code makes network requests | Network access is blocked, by namespaces on Linux and Seatbelt on macOS |
| The code needs your APIs or databases | You register tool functions, which run in your session |
| The code runs forever | A timeout stops it, and the session restarts so you can keep using it |
| The code uses all your memory | Resource limits, with `ulimit` on Linux and macOS and Job Objects on Windows |
| The code doesn't parse | It's checked for syntax errors before it's sent to the sandbox |

Posit's commons package has its own sandbox for its built-in agents, but you
can't reuse it for an agent you write yourself. securer is meant for that
case.

## How it works

```{=html}
<figure class="hairline">
<svg role="img" aria-label="Host sends code to the sandboxed child; the child pauses on a tool call, the host runs it, sends the result back, and the child returns the final value" viewBox="0 0 900 292" xmlns="http://www.w3.org/2000/svg"><defs>
<marker id="tc-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
<path d="M1 1L9 5L1 9" fill="none" stroke="#2b1f12" stroke-width="1"/></marker>
<pattern id="tc-hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
<line x1="0" y1="0" x2="0" y2="6" stroke="#bf5a36" stroke-width="0.6" opacity="0.55"/></pattern>
</defs><rect x="440" y="20" width="440" height="258" fill="url(#tc-hatch)" opacity="0.35" stroke="none"/><rect x="440" y="20" width="440" height="258" fill="none" stroke="#bf5a36" stroke-width="0.75" stroke-dasharray="4 3"/><text x="872" y="36" font-family="Space Mono, ui-monospace, monospace" font-size="8.5" fill="#bf5a36" text-anchor="end" font-weight="400" letter-spacing="1.6" >OS SANDBOX</text><rect x="140" y="40" width="180" height="36" fill="none" stroke="#2b1f12" stroke-width="0.75"/><text x="230.0" y="62.0" font-family="Space Mono, ui-monospace, monospace" font-size="10.5" fill="#2b1f12" text-anchor="middle" font-weight="700" letter-spacing="1.2" >HOST R SESSION</text><rect x="500" y="40" width="180" height="36" fill="none" stroke="#2b1f12" stroke-width="0.75"/><text x="590.0" y="62.0" font-family="Space Mono, ui-monospace, monospace" font-size="10.5" fill="#2b1f12" text-anchor="middle" font-weight="700" letter-spacing="1.2" >CHILD R PROCESS</text><path d="M230 76V274M590 76V274" stroke="#6b5638" stroke-width="0.6" stroke-dasharray="1 3"/><path d="M230 132H588" fill="none" stroke="#2b1f12" stroke-width="0.75" marker-end="url(#tc-arrow)"/><text x="410.0" y="125" font-family="Space Mono, ui-monospace, monospace" font-size="9.5" fill="#2b1f12" text-anchor="middle" font-weight="400" letter-spacing="0.8" >SEND THE CODE</text><text x="604" y="136" font-family="Space Mono, ui-monospace, monospace" font-size="9" fill="#6b5638" text-anchor="start" font-weight="400" letter-spacing="0.3" >runs it</text><path d="M590 172H232" fill="none" stroke="#2b1f12" stroke-width="0.75" marker-end="url(#tc-arrow)"/><text x="410.0" y="165" font-family="Space Mono, ui-monospace, monospace" font-size="9.5" fill="#2b1f12" text-anchor="middle" font-weight="400" letter-spacing="0.8" >TOOL CALL</text><text x="216" y="176" font-family="Space Mono, ui-monospace, monospace" font-size="9" fill="#6b5638" text-anchor="end" font-weight="400" letter-spacing="0.3" >runs your tool function</text><text x="604" y="176" font-family="Space Mono, ui-monospace, monospace" font-size="9" fill="#6b5638" text-anchor="start" font-weight="400" letter-spacing="0.3" >pauses on the socket</text><path d="M230 212H588" fill="none" stroke="#2b1f12" stroke-width="0.75" marker-end="url(#tc-arrow)"/><text x="410.0" y="205" font-family="Space Mono, ui-monospace, monospace" font-size="9.5" fill="#2b1f12" text-anchor="middle" font-weight="400" letter-spacing="0.8" >TOOL RESULT</text><text x="604" y="216" font-family="Space Mono, ui-monospace, monospace" font-size="9" fill="#6b5638" text-anchor="start" font-weight="400" letter-spacing="0.3" >carries on</text><path d="M590 252H232" fill="none" stroke="#2b1f12" stroke-width="0.75" marker-end="url(#tc-arrow)"/><text x="410.0" y="245" font-family="Space Mono, ui-monospace, monospace" font-size="9.5" fill="#2b1f12" text-anchor="middle" font-weight="400" letter-spacing="0.8" >FINAL VALUE</text><text x="216" y="256" font-family="Space Mono, ui-monospace, monospace" font-size="9" fill="#6b5638" text-anchor="end" font-weight="400" letter-spacing="0.3" >hands it back to you</text></svg>
<figcaption>Fig. 1 &middot; A tool call: the code runs in the child, your function runs in the host</figcaption>
</figure>
```

The two processes talk over a Unix domain socket. A tool call blocks the
child until the parent sends back the result.

## Features

### Sessions

Starting a sandboxed R process takes a moment. Keep one open to run several
pieces of code:

```r
session <- SecureSession$new(tools = tools, sandbox = TRUE)

session$execute('query_db("iris", 3)')
session$execute('query_db("mtcars", 5)')

session$close()
```

### Session pools

If you run many requests at once, start a few sessions ahead of time:

```r
pool <- SecureSessionPool$new(size = 4, tools = tools, sandbox = TRUE)

result <- pool$execute('query_db("iris", 3)')

pool$close()
```

### Resource limits

Cap CPU time, memory, file size, and more. Limits work on every platform,
with or without the sandbox:

```r
result <- execute_r("1 + 1",
  limits = list(cpu = 10, memory = 256 * 1024 * 1024)
)
```

### Timeouts

Code that runs too long is stopped. The session restarts itself, so you can
use it again straight away:

```r
session <- SecureSession$new()
session$execute("Sys.sleep(100)", timeout = 5)
# Error: Execution timed out after 5 seconds
session$execute("1 + 1")  # still works
```

### Syntax checks

Code that doesn't parse fails right away, without a trip to the child
process:

```r
session$execute("if (TRUE {")  # immediate error
```

### ellmer

Give an [ellmer](https://ellmer.tidyverse.org/) chat a tool that runs R
code in the sandbox:

```r
library(ellmer)
chat <- chat_openai()
chat$register_tool(as_ellmer_tool())
chat$chat("Calculate the mean of 1 through 100 using R")
```

### Audit log

Write every session event to a JSONL file, one JSON object per line:

```r
session <- SecureSession$new(audit_log = "session.jsonl")
```

### Verbose mode

Print what the session is doing as it happens:

```r
session <- SecureSession$new(tools = tools, verbose = TRUE)
session$execute('query_db("iris", 3)')
# [securer] Session started (sandbox=false, pid=1234)
# [securer] Tool call: query_db(table=iris, limit=3)
# [securer] Tool result: query_db -> ... (0.00s)
# [securer] Execution complete (0.27s)
```

## Platform support

| Platform | Sandbox | Network blocked | Filesystem restricted | Resource limits |
|---|---|---|---|---|
| Linux | bubblewrap (`bwrap`) | Yes | Yes | Yes (`ulimit`) |
| macOS | Seatbelt (`sandbox-exec`) | Yes | Yes | Yes (`ulimit`) |
| Windows | Job Objects and a clean environment | No | No | Yes (memory, CPU, process count) |
| docker-spawn (any host) | A new container per session | Yes (`--network=none`) | Yes (container filesystem) | Yes (`--memory`, `--cpus`, `ulimit`) |

Tool calls, timeouts, and syntax checks work everywhere.

On Windows, securer can only clean the environment and set resource limits.
It can't stop the code from reading files or using the network. If you need
that on Windows, use the docker-spawn backend or a Linux VM.

The docker-spawn backend is off by default. Turn it on with
`SECURER_SANDBOX_MODE=docker-spawn`. It needs the `docker` command and a
running Docker daemon. `inst/docker/Dockerfile` has a reference image.

## Security

The sandbox is one of several protections. securer also checks that only
the child it started can connect to the socket, limits resources, strips
secrets from the child's environment, and checks tool arguments. The
security model vignette (`vignette("security-model", package = "securer")`)
covers what securer protects against and what it doesn't.

To report a security problem, email the maintainer instead of opening a
public issue.

## Related packages

securer is part of a small set of packages for running LLM agents in R
more safely:

- [secureguard](https://github.com/ian-flores/secureguard) checks prompts, generated code, and outputs for things like prompt injection and leaked secrets.
- [securetools](https://github.com/ian-flores/securetools) has ready-made tools (file access, SQL, web requests) with limits built in.
- [securebench](https://github.com/ian-flores/securebench) measures how well your guardrails work. It complements [vitals](https://vitals.tidyverse.org/).

They build on Posit's tools rather than replacing them. For tracing, use
[ellmer](https://ellmer.tidyverse.org/)'s OpenTelemetry support through the
[otel](https://otel.r-lib.org/) package. For retrieval (RAG), use
[ragnar](https://github.com/tidyverse/ragnar).

## Learn more

- `vignette("quickstart", package = "securer")`: installing and first examples
- `vignette("sessions-and-tools", package = "securer")`: sessions, streaming output, and pools
- `vignette("deployment", package = "securer")`: sandboxes, resource limits, and how the pieces fit
- `vignette("security-model", package = "securer")`: what securer protects against
- `vignette("ellmer-integration", package = "securer")`: using securer with ellmer chats
- `vignette("integration-examples", package = "securer")`: Shiny, Plumber, and batch jobs
- `vignette("troubleshooting", package = "securer")`: common problems
- [Function reference](https://ian-flores.github.io/securer/reference/)

Found a bug or have an idea? [Open an issue](https://github.com/ian-flores/securer/issues).

## License

MIT
