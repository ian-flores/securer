# Troubleshooting

## Common problems

### “bwrap: No such file or directory” or “sandbox-exec not found”

The sandbox tool for your platform is missing. On Linux, securer needs
bubblewrap (`bwrap`). On macOS it uses `sandbox-exec`, which comes with
the OS, so you shouldn’t see this there.

``` r

# Linux: install bubblewrap
# Debian/Ubuntu: sudo apt install bubblewrap
# Fedora:        sudo dnf install bubblewrap

# With sandbox_strict = TRUE, a missing sandbox is an error, not a warning
session <- SecureSession$new(sandbox = TRUE, sandbox_strict = TRUE)
```

If you’d rather run without the sandbox when the tool is missing, leave
`sandbox_strict = FALSE`, the default. securer warns you and carries on.

### “Timeout waiting for client connection”

The child R process didn’t connect to the socket within a few seconds.
Usually that means the child failed to start, often because the sandbox
wrapper couldn’t run.

The socket path isn’t the problem. On macOS and Linux, securer always
puts the socket in a new directory under `/tmp`, whatever `TMPDIR` is
set to, because macOS limits socket paths to about 104 characters.

``` r

# /tmp has to be writable
file.access("/tmp", 2) == 0

# If this works, the sandbox is what's failing
session <- SecureSession$new(sandbox = FALSE)
```

### “Session is not running”

The child R process has stopped. The OS may have killed it for using too
much memory, it may have hit a resource limit, or something else sent it
a signal.

``` r

session <- SecureSession$new(sandbox = TRUE)

# Check whether the child process is still alive
session$is_alive()

# After a timeout, securer restarts the session by itself.
# After any other crash, start a new one:
session$close()
session <- SecureSession$new(sandbox = TRUE)
```

### Windows sandbox limitations

On Windows, securer only cleans the child’s environment (`HOME`,
`TMPDIR`, and `R_LIBS_USER`, among others) and sets resource limits with
Job Objects. It doesn’t restrict files or the network.

To get those restrictions, set `SECURER_SANDBOX_MODE=docker-spawn` so
each session runs in its own Docker container. Or run R inside WSL2 with
bubblewrap installed:

``` r

# Inside WSL2 with bwrap installed, securer uses the Linux sandbox backend
session <- SecureSession$new(sandbox = TRUE, sandbox_strict = TRUE)
```

### “Maximum executions (N) reached for this session”

The session has run code as many times as `max_executions` allows. The
limit is for throwaway agent sessions, where you want a hard cap on how
often code can run.

``` r

# This session allows only 5 executions
session <- SecureSession$new(max_executions = 5)

# After 5 calls to $execute(), the next one is an error.
# Start a new session:
session$close()
session <- SecureSession$new(max_executions = 10)

# Or leave out the limit:
session <- SecureSession$new()
```

### “Execution blocked by pre_execute_hook”

Your `pre_execute_hook` returned `FALSE` for this code. To see why, call
the hook yourself on the code that was rejected.

``` r

# Example hook that blocks system() calls
my_hook <- function(code) {
  if (grepl("system\\(", code)) return(FALSE)
  TRUE
}

# Call it directly to see what it rejects
my_hook("x <- 1 + 1")          # TRUE: allowed
my_hook("system('whoami')")     # FALSE: blocked

session <- SecureSession$new(pre_execute_hook = my_hook)
```

Only `FALSE` blocks the code. Anything else the hook returns, `NULL`
included, lets it run.

### “Package ‘foo’ not found” in child process

securer empties `R_LIBS_USER` in the child on purpose, so a package in a
user library can’t run code when it loads. Inside the sandbox you only
get packages from `R_LIBS_SITE` and `R.home("library")`.

``` r

# Option 1: Install the package system-wide
# install.packages("foo", lib = .Library)

# Option 2: Register a tool that uses the package in your session
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

[`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
starts and stops a session every time you call it. If you run code many
times, keep one session open or use a pool.

``` r

# Slow: a new session for every call
for (i in 1:100) {
  execute_r(paste("sqrt(", i, ")"))
}

# Fast: one session, reused
session <- SecureSession$new()
for (i in 1:100) {
  session$execute(paste("sqrt(", i, ")"))
}
session$close()

# Fast, and handles several callers at once: a pool
pool <- SecureSessionPool$new(size = 4)
for (i in 1:100) {
  pool$execute(paste("sqrt(", i, ")"))
}
pool$close()
```

### “IPC authentication failed”

Whatever connected to the socket first didn’t send the random token
securer gave the child. Either the child failed before it could send it,
or another process on the machine connected first.

securer creates each socket directory with `0700` permissions, so only
your user can get in. On a shared machine, check that those directories
really are private.

``` r

# Socket directories are /tmp/securer_*. Check their permissions with:
# ls -ld /tmp/securer_*
```

### “Audit log not written”

Pass `audit_log` when you create the session. The directory it goes in
has to exist and be writable. securer creates the file with `0600`
permissions and refuses a path that’s a symlink.

``` r

# Make sure the directory exists
dir.create("logs", showWarnings = FALSE)

session <- SecureSession$new(
  audit_log = "logs/securer-audit.jsonl"
)

session$execute("1 + 1")
session$close()

# Check the log was written
readLines("logs/securer-audit.jsonl")
```
