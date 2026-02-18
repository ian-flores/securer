# securer — Development Guide

## What This Is

An R package for secure LLM code execution. LLMs write R code that calls
registered tools as functions. Execution pauses at each tool call, the
host fulfills it, and execution resumes. The child R process runs inside
an OS sandbox.

## Architecture

    SecureSession (R6)
    ├── callr::r_session — child R process
    ├── Unix domain socket — bidirectional IPC (tool calls + responses)
    ├── Tool registry — securer_tool() objects → child wrapper functions + type checking
    ├── Sandbox — macOS Seatbelt / Linux bwrap / Windows env isolation
    ├── Resource limits — ulimit-based CPU, memory, fsize, nproc, nofile, stack
    ├── Execution timeouts — deadline-based abort with session recovery
    ├── Verbose logging — optional structured message() output
    ├── Code pre-validation — syntax check + dangerous pattern warnings
    ├── Streaming output — capture cat()/print() via piped stdout/stderr
    ├── File-based audit log — JSONL event log for compliance/debugging
    └── ellmer integration — securer_as_ellmer_tool() for LLM chat

    SecureSessionPool (R6)
    └── Pre-warmed pool of SecureSession instances for low-latency execution

Key files: - `R/secure-session.R` — Core R6 class, event loop, session
lifecycle - `R/child-runtime.R` — Code string injected into child
(`.securer_call_tool()`) - `R/ipc.R` — UDS helpers (create, accept,
read, write) - `R/tool-registry.R` —
[`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md),
validation, wrapper code generation - `R/sandbox-macos.R` — Seatbelt
profile generation + wrapper script - `R/sandbox-linux.R` — Bubblewrap
(bwrap) namespace isolation + wrapper script - `R/sandbox-windows.R` —
Environment-variable-only isolation for Windows - `R/rlimits.R` — ulimit
command generation and validation - `R/execute.R` —
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
convenience function - `R/validate.R` — Code pre-validation (syntax +
dangerous patterns) - `R/audit-log.R` — JSONL file-based audit logging -
`R/session-pool.R` — SecureSessionPool R6 class - `R/ellmer.R` — ellmer
tool integration
([`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md))

Vignettes: - `vignettes/quickstart.Rmd` — Installation and first
examples - `vignettes/sessions-and-tools.Rmd` — Persistent sessions,
streaming, pooling, audit log - `vignettes/deployment.Rmd` — Sandboxing,
resource limits, architecture - `vignettes/security-model.Rmd` — Full
threat model and defense layers (~600 lines) -
`vignettes/ellmer-integration.Rmd` — ellmer LLM chat integration -
`vignettes/integration-examples.Rmd` — Shiny, Plumber, batch examples -
`vignettes/troubleshooting.Rmd` — FAQ and common issues

## Critical Implementation Details

### Unix Domain Socket Behavior

`processx::conn_accept_unix_socket(server)` does NOT return a new
connection. It transitions the server connection in-place to
“connected_server” state. The same object is used for bidirectional
data. This is why `SecureSession` uses a single `ipc_conn` field.

### Sandbox Wrapper Trick

`callr::r_session_options(arch = "/path/to/wrapper.sh")` — callr treats
`arch` values containing `/` as direct paths to the R binary. We exploit
this to inject `sandbox-exec -f profile.sb R "$@"` as the “R binary.”

### Socket Path Length

Unix domain sockets are limited to ~104 chars on macOS. We use `/tmp`
directly instead of [`tempdir()`](https://rdrr.io/r/base/tempfile.html)
(which can be deeply nested during `R CMD check`).

### Child Runtime

[`child_runtime_code()`](https://ian-flores.github.io/securer/reference/child_runtime_code.md)
returns a CHARACTER STRING, not functions. It’s `eval(parse(text=...))`
in the child’s global environment. Tool wrappers are injected the same
way after the UDS connects.

### Event Loop

`run_with_tools()` polls the UDS for tool-call JSON and the callr
process for completion in a loop with 200ms poll intervals. Tool calls
are synchronous: child blocks on UDS read, parent executes tool, writes
result back.

### Execution Timeouts

`$execute(code, timeout = N)` tracks elapsed time in the event loop. On
timeout, the child process is killed, the UDS is cleaned up, and the
session is automatically restarted so it remains usable for subsequent
calls.

### Tool Argument Type Checking

Tool wrappers generated for the child process include runtime type
validation when `args` have type annotations (e.g.,
`args = list(x = "numeric")`). Supported types: numeric, character,
logical, integer, list, data.frame. Mismatches produce clear errors
before the tool call is dispatched.

### Verbose Logging

`SecureSession$new(verbose = TRUE)` logs lifecycle events via
[`message()`](https://rdrr.io/r/base/message.html): session start/close,
tool calls with args and timing, execution completion, errors, and
timeouts. Users can suppress with
[`suppressMessages()`](https://rdrr.io/r/base/message.html).

### Concurrent Execution Guard

A private `executing` flag prevents parallel `$execute()` calls on the
same session. The flag is reset via
[`on.exit()`](https://rdrr.io/r/base/on.exit.html) to guarantee cleanup
even on errors.

### Code Pre-Validation

`$execute(code, validate = TRUE)` parses code with `parse(text=)` before
sending to the child, catching syntax errors immediately. Also warns on
dangerous patterns ([`system()`](https://rdrr.io/r/base/system.html),
[`.Internal()`](https://rdrr.io/r/base/Internal.html), etc.) — advisory
only, the sandbox handles actual restriction.

### Streaming Output

`$execute(code, output_handler = function(line) ...)` pipes child
stdout/stderr and drains output each event loop iteration. Output is
also available as `attr(result, "output")` on the return value.

### File-Based Audit Log

`SecureSession$new(audit_log = "/path/to/log.jsonl")` writes structured
JSONL entries for session lifecycle, tool calls, and execution events.
Each session gets a unique `session_id` for correlation.

### Session Pooling

`SecureSessionPool$new(size = 4)` pre-warms N sessions. `$execute()`
acquires an idle session, runs code, and returns it to the pool. Dead
sessions are auto-restarted on acquire.

### ellmer Integration

[`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md)
wraps a SecureSession as an
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definition. Errors are returned as `ContentToolResult(error=...)` so
they don’t crash the LLM chat. ellmer is a soft dependency (Suggests).

## Development Commands

``` bash
# Run tests
Rscript -e "devtools::test('.')"

# Run R CMD check
Rscript -e "devtools::check('.')"

# Regenerate docs (after roxygen changes)
Rscript -e "devtools::document('.')"

# Load for interactive testing
Rscript -e "devtools::load_all('.')"
```

## Test Structure

- `test-secure-session.R` — Session lifecycle, timeouts, concurrent
  execution guard
- `test-ipc.R` — Tool call pause/resume via `.securer_call_tool()`
  directly
- `test-tool-registry.R` — securer_tool(), validation, wrappers, type
  checking, end-to-end
- `test-sandbox.R` — Sandbox restrictions (macOS/Linux/Windows), rlimits
- `test-execute.R` —
  [`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
  convenience API
- `test-logging.R` — Verbose logging output verification
- `test-validate.R` — Code pre-validation (syntax errors, dangerous
  patterns)
- `test-audit-log.R` — JSONL audit log events and structure
- `test-session-pool.R` — Pool lifecycle, acquire/release, error
  recovery
- `test-ellmer.R` — ellmer tool definition, execution, error handling

## Platform Notes

- **macOS**: Full sandbox via Seatbelt. Requires
  `/usr/bin/sandbox-exec`.
- **Linux**: Full sandbox via bubblewrap (`bwrap`). Requires `bwrap` on
  PATH.
- **Windows**: Environment isolation only (clean HOME/TMPDIR, empty
  R_LIBS_USER). No filesystem/network restrictions.

Sandbox tests use `skip_on_os()` and `skip_if_not()` to gate
platform-specific tests.

## Known Limitations

- Windows sandbox provides environment isolation only — no filesystem or
  network restrictions without admin privileges
- Single concurrent session per `SecureSession` instance — concurrent
  `$execute()` calls are detected and rejected with an error
