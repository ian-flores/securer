# Troubleshooting

## Common Issues and Solutions

This vignette covers the most frequently encountered problems when using
securer and how to resolve them.

### “bwrap: No such file or directory” / “sandbox-exec not found”

The sandbox backend is missing for your platform. On Linux, securer uses
bubblewrap (`bwrap`) for namespace isolation. On macOS, `sandbox-exec`
ships with the OS and should already be available.

``` r
# Linux -- install bubblewrap
# Debian/Ubuntu: sudo apt install bubblewrap
# Fedora:        sudo dnf install bubblewrap

# Use sandbox_strict = TRUE to get a hard error instead of a silent fallback
session <- SecureSession$new(sandbox = TRUE, sandbox_strict = TRUE)
```

If you want the session to proceed without sandboxing when tools are
missing, leave `sandbox_strict = FALSE` (the default) — securer will
emit a warning and continue unsandboxed.

### “Socket connection timed out”

Unix domain socket paths are limited to approximately 104 characters on
macOS. securer creates sockets in `/tmp` directly to keep paths short.
If you have overridden `TMPDIR` or
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) to a deeply nested
directory, the resulting socket path may exceed this limit.

``` r
# Check your current tempdir length
nchar(tempdir())
# If this exceeds ~80 characters, reset TMPDIR before creating a session
Sys.setenv(TMPDIR = "/tmp")
session <- SecureSession$new()
```

### “Session is not running”

The child R process has exited unexpectedly. This can happen when the
child is killed by the OS (out-of-memory), hits a resource limit, or
receives an external signal.

``` r
session <- SecureSession$new(sandbox = TRUE)

# Check whether the child process is still alive
session$is_alive()

# After a timeout, securer auto-restarts the session automatically.
# For other crashes, create a fresh session:
session$close()
session <- SecureSession$new(sandbox = TRUE)
```

### Windows sandbox limitations

On Windows, securer provides environment isolation only — environment
variables are sanitized (`HOME`, `TMPDIR`, `R_LIBS_USER`) and resource
limits are applied via Job Objects. There are **no** filesystem or
network restrictions.

For full isolation on Windows, run your R process inside Docker or WSL2
with bubblewrap:

``` r
# Inside WSL2 with bwrap installed, securer uses the Linux sandbox backend
session <- SecureSession$new(sandbox = TRUE, sandbox_strict = TRUE)
```

### “Maximum executions (N) reached for this session”

The `max_executions` safety limit has been reached. This feature exists
for disposable agent sessions where you want to cap how many times code
can run.

``` r
# This session allows only 5 executions
session <- SecureSession$new(max_executions = 5)

# After 5 calls to $execute(), further calls will error.
# Either create a new session:
session$close()
session <- SecureSession$new(max_executions = 10)

# Or omit the limit entirely for unlimited executions:
session <- SecureSession$new()
```

### “Execution blocked by pre_execute_hook”

Your `pre_execute_hook` function returned `FALSE`, which blocks
execution. Debug by testing the hook directly with the code string that
was rejected.

``` r
# Example hook that blocks system() calls
my_hook <- function(code) {
  if (grepl("system\\(", code)) return(FALSE)
  TRUE
}

# Test it directly to understand what triggers rejection
my_hook("x <- 1 + 1")          # TRUE -- allowed
my_hook("system('whoami')")     # FALSE -- blocked

session <- SecureSession$new(pre_execute_hook = my_hook)
```

Any return value other than `FALSE` (including `NULL` or `TRUE`) allows
execution to proceed.

### “Package ‘foo’ not found” in child process

The child process runs with `R_LIBS_USER` deliberately emptied for
security. Only system-level packages (from `R_LIBS_SITE` and
`R.home("library")`) are available inside the sandbox.

``` r
# Option 1: Install the package system-wide
# install.packages("foo", lib = .Library)

# Option 2: Register a tool that calls the package on the host side
tools <- list(
  securer_tool(
    name = "run_foo",
    description = "Run foo::bar() on the host",
    fn = function(x) foo::bar(x),
    args = list(x = "character")
  )
)
session <- SecureSession$new(tools = tools, sandbox = TRUE)
session$execute('run_foo("input")')
```

### Slow session startup

The
[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
convenience function creates and tears down a session for every call.
For repeated executions, reuse a persistent session or use a pool.

``` r
# Slow -- new session per call
for (i in 1:100) {
  execute_r(paste("sqrt(", i, ")"))
}

# Fast -- reuse a single session
session <- SecureSession$new()
for (i in 1:100) {
  session$execute(paste("sqrt(", i, ")"))
}
session$close()

# Fast with concurrency management -- use a pool
pool <- SecureSessionPool$new(size = 4)
for (i in 1:100) {
  pool$execute(paste("sqrt(", i, ")"))
}
pool$close()
```

### “IPC authentication failed”

The child process failed to present the correct authentication token
when connecting to the Unix domain socket. This typically means another
process on the system connected to the socket before the legitimate
child did.

securer creates socket directories with `0700` permissions to prevent
this. If you are on a shared system, ensure `/tmp` subdirectories are
not world-accessible.

``` r
# Verify socket directory permissions
session <- SecureSession$new(verbose = TRUE)
# Verbose mode logs the socket path -- check its permissions with:
# ls -la /tmp/securer_sock_*
```

### “Audit log not written”

The `audit_log` path must be passed at session creation time. Ensure the
parent directory exists and is writable. The log file is created with
`0600` permissions, and symlinks are rejected for security.

``` r
# Ensure the directory exists
dir.create("logs", showWarnings = FALSE)

session <- SecureSession$new(
  audit_log = "logs/securer-audit.jsonl"
)

session$execute("1 + 1")
session$close()

# Verify the log was written
readLines("logs/securer-audit.jsonl")
```
