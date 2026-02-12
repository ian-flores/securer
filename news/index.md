# Changelog

## securer 0.1.0

Initial release.

### Core Features

- `SecureSession` R6 class for persistent sandboxed R sessions with
  tool-call IPC over Unix domain sockets.
- `SecureSessionPool` for pre-warmed session pools with automatic
  dead-session recovery.
- [`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
  convenience function for one-shot sandboxed execution.
- [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  for defining typed tool functions with runtime argument validation.
- [`validate_code()`](https://ian-flores.github.io/securer/reference/validate_code.md)
  for pre-execution syntax checking and dangerous pattern detection.
- [`default_limits()`](https://ian-flores.github.io/securer/reference/default_limits.md)
  for inspecting and customizing resource limit defaults.

### Session Ergonomics

- `$restart()` method to explicitly restart a dead or stuck child
  process.
- `$tools()` accessor to inspect registered tools and their argument
  specs.
- [`print()`](https://rdrr.io/r/base/print.html)/[`format()`](https://rdrr.io/r/base/format.html)
  methods for `SecureSession` and `SecureSessionPool`.
- `sandbox_strict` parameter to error when sandbox tools are unavailable
  instead of silently falling back to unsandboxed execution.

### Sandbox Support

- **macOS**: Full OS-level sandbox via Seatbelt (`sandbox-exec`) -
  filesystem writes blocked, network denied, reads restricted to R
  libraries.
- **Linux**: Full namespace isolation via bubblewrap (`bwrap`) -
  read-only mounts, network namespace isolation, `/tmp`-only writes.
- **Windows**: Environment variable isolation (clean HOME, empty
  R_LIBS_USER) plus Job Object resource limits (memory, CPU time,
  process count) via PowerShell.

### Resource Controls

- `ulimit`-based resource limits on Unix: CPU time, memory, file size,
  process count, open files, stack size.
- Windows Job Object limits: memory, CPU time, active process count.
- Execution timeouts with automatic session recovery.
- Concurrent execution guard preventing parallel `$execute()` on the
  same session.

### Security Hardening

- IPC token authentication on Unix domain sockets.
- Socket directory restricted to 0700 permissions.
- Tool name and argument injection prevention.
- Environment variable sanitization (R_LIBS, R_PROFILE, etc.).
- Binding locks on injected runtime functions and tool wrappers in the
  child process.
- IPC message size limits and schema validation.

### Integrations

- [`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md)
  for using securer as a code execution tool in ellmer LLM chats. Errors
  returned as `ContentToolResult(error=...)`.

### Observability

- File-based JSONL audit logging for session lifecycle, tool calls, and
  execution events.
- Verbose [`message()`](https://rdrr.io/r/base/message.html) logging for
  debugging (tool call timing, lifecycle events).
- Streaming output capture from child
  [`cat()`](https://rdrr.io/r/base/cat.html)/[`print()`](https://rdrr.io/r/base/print.html)
  via piped stdout/stderr.
