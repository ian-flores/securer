# securer — Development Guide

## What This Is

An R package for secure LLM code execution. LLMs write R code that calls registered tools as functions. Execution pauses at each tool call, the host fulfills it, and execution resumes. The child R process runs inside an OS sandbox.

## Architecture

```
SecureSession (R6)
├── callr::r_session — child R process
├── Unix domain socket — bidirectional IPC (tool calls + responses)
├── Tool registry — securer_tool() objects → child wrapper functions
├── Sandbox — macOS Seatbelt / Linux bwrap / Windows env isolation
└── Resource limits — ulimit-based CPU, memory, fsize, nproc, nofile, stack
```

Key files:
- `R/secure-session.R` — Core R6 class, event loop, session lifecycle
- `R/child-runtime.R` — Code string injected into child (`.securer_call_tool()`)
- `R/ipc.R` — UDS helpers (create, accept, read, write)
- `R/tool-registry.R` — `securer_tool()`, validation, wrapper code generation
- `R/sandbox-macos.R` — Seatbelt profile generation + wrapper script
- `R/sandbox-linux.R` — Bubblewrap (bwrap) namespace isolation + wrapper script
- `R/sandbox-windows.R` — Environment-variable-only isolation for Windows
- `R/rlimits.R` — ulimit command generation and validation
- `R/execute.R` — `execute_r()` convenience function

## Critical Implementation Details

### Unix Domain Socket Behavior
`processx::conn_accept_unix_socket(server)` does NOT return a new connection. It transitions the server connection in-place to "connected_server" state. The same object is used for bidirectional data. This is why `SecureSession` uses a single `ipc_conn` field.

### Sandbox Wrapper Trick
`callr::r_session_options(arch = "/path/to/wrapper.sh")` — callr treats `arch` values containing `/` as direct paths to the R binary. We exploit this to inject `sandbox-exec -f profile.sb R "$@"` as the "R binary."

### Socket Path Length
Unix domain sockets are limited to ~104 chars on macOS. We use `/tmp` directly instead of `tempdir()` (which can be deeply nested during `R CMD check`).

### Child Runtime
`child_runtime_code()` returns a CHARACTER STRING, not functions. It's `eval(parse(text=...))` in the child's global environment. Tool wrappers are injected the same way after the UDS connects.

### Event Loop
`run_with_tools()` polls the UDS for tool-call JSON and the callr process for completion in a loop with 200ms poll intervals. Tool calls are synchronous: child blocks on UDS read, parent executes tool, writes result back.

## Development Commands

```bash
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

- `test-secure-session.R` — Session lifecycle (start, execute, close, errors)
- `test-ipc.R` — Tool call pause/resume via `.securer_call_tool()` directly
- `test-tool-registry.R` — securer_tool(), validation, wrappers, end-to-end
- `test-sandbox.R` — Sandbox restrictions (macOS/Linux/Windows), rlimits
- `test-execute.R` — `execute_r()` convenience API

## Platform Notes

- **macOS**: Full sandbox via Seatbelt. Requires `/usr/bin/sandbox-exec`.
- **Linux**: Full sandbox via bubblewrap (`bwrap`). Requires `bwrap` on PATH.
- **Windows**: Environment isolation only (clean HOME/TMPDIR, empty R_LIBS_USER). No filesystem/network restrictions.

Sandbox tests use `skip_on_os()` and `skip_if_not()` to gate platform-specific tests.

## Known Limitations

- Windows sandbox provides environment isolation only — no filesystem or network restrictions without admin privileges
- Single concurrent session per `SecureSession` instance — concurrent `$execute()` calls are detected and rejected with an error
