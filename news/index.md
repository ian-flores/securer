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

- IPC token authentication on Unix domain sockets using cryptographic
  randomness (`/dev/urandom` on Unix,
  [`sample()`](https://rdrr.io/r/base/sample.html) fallback on Windows).
- Closure-based UDS connection hiding in the child process — the
  connection object is invisible to child code (no global
  `.securer_env`).
- `unlockBinding` shadowed in child to prevent tampering with locked
  bindings.
- `SECURER_TOKEN` and `SECURER_SOCKET` environment variables cleared
  after authentication so child code cannot read credentials.
- macOS Seatbelt profile hardened: `/bin/bash` removed from allowed
  executables, `/opt/homebrew` narrowed to `lib/Cellar/opt`, `/dev`
  restricted to specific device nodes, `mach*`/`iokit*`/`sysctl*` scoped
  to least-privilege operations.
- Socket directory enforced to 0700 permissions (immune to umask).
- Wrapper scripts and Seatbelt profiles set to owner-only (0700/0600).
- IPC rate limiting to prevent message flood attacks.
- Unknown IPC message types logged as warnings.
- Tool name regex validation and
  [`.Deprecated()`](https://rdrr.io/r/base/Deprecated.html) warning for
  legacy tool format.
- Zero-argument tools reject unexpected arguments.
- `R_LIBS` and `R_LIBS_USER` excluded from child environment allowlist
  to prevent library injection via `.onLoad` hooks.
- Audit log path validated for symlinks, device files, and path
  traversal.
- Audit log code field truncated to prevent unbounded growth.
- Audit log files created with 0600 permissions.
- Audit log tool results include truncated return value summary for
  forensics.
- `output_handler` validated upfront and wrapped in `tryCatch` to
  prevent handler errors from corrupting session state.
- Tool error messages sanitized before returning to child process
  (strips file paths, PIDs, IPs, and stack traces).
- Windows sandbox emits an explicit warning about limited isolation
  scope.
- Session pool size capped at 100 to prevent resource exhaustion.

### Integrations

- [`securer_as_ellmer_tool()`](https://ian-flores.github.io/securer/reference/securer_as_ellmer_tool.md)
  for using securer as a code execution tool in ellmer LLM chats. Error
  messages sanitized before returning to the LLM (strips file paths,
  PIDs, hostnames, and stack traces).

### Observability

- File-based JSONL audit logging for session lifecycle, tool calls (with
  truncated result summaries), and execution events. Logs validated and
  created with restrictive file permissions.
- `SecureSessionPool$status()` method returning total/busy/idle/dead
  counts.
- `$execute(acquire_timeout = N)` for session pool with configurable
  wait time.
- Verbose [`message()`](https://rdrr.io/r/base/message.html) logging for
  debugging (tool call timing, lifecycle events).
- Streaming output capture from child
  [`cat()`](https://rdrr.io/r/base/cat.html)/[`print()`](https://rdrr.io/r/base/print.html)
  via piped stdout/stderr.
