# Approach A: callr + OS Sandbox -- Full Analysis

## Executive Summary

Approach A proposes using Posit's own `callr::r_session` as the execution engine for LLM-generated R code, wrapped in OS-level sandbox restrictions (seccomp/namespaces on Linux, Seatbelt on macOS). It mirrors Pydantic Monty's architectural pattern -- pause/resume execution with external function calls -- but adapts it to R's reality: we can't rewrite R in Rust, but we *can* control the process boundary around a real R interpreter.

---

## 1. Architecture

### Core Components

```
Host Process (R or Python)
  |
  +-- callr::r_session (pre-warmed R subprocess)
  |     |-- IPC via fd3 pipe (processx)
  |     |-- stdout/stderr capture
  |     |-- poll() for async monitoring
  |     +-- run()/call()/read() for command dispatch
  |
  +-- OS Sandbox Layer
  |     |-- Linux: seccomp-bpf + namespaces + Landlock
  |     |-- macOS: sandbox-exec with Seatbelt profiles
  |     +-- Network: proxy-based filtering (a la Anthropic's srt)
  |
  +-- Tool Registry
        |-- R functions registered as "external calls"
        |-- Pause execution on tool invocation
        |-- Resume with result after host-side execution
```

### How It Works

1. **Pre-warm**: Start `callr::r_session$new()` inside an OS sandbox. R boots in ~100-300ms. The session idles, ready for commands.

2. **Inject LLM code**: The host sends LLM-generated R code via `$call()` (async) or `$run()` (sync). Code executes in the sandboxed subprocess.

3. **Tool calls (pause/resume)**: When LLM code calls a registered tool function, the function sends a MSG (code 301) condition back to the host via fd3, then blocks waiting for a response. The host reads the message, executes the tool, and writes the result back. The subprocess resumes.

4. **Completion**: When execution finishes, the host reads the result via `$read()` (code 200).

### IPC Deep Dive

callr's IPC is surprisingly rich:

- **fd3 pipe**: A dedicated file descriptor (separate from stdout/stderr) for structured messages between parent and child. Messages have a header format: `[code] [length] [rest]` followed by body data.
- **Code 301 (MSG)**: Custom condition objects can be serialized via base64 and sent from child to parent. The parent can register handlers via `getOption("callr.condition_handler_[class]")`.
- **signalCondition() + restarts**: R's condition system allows the child to signal a condition, the parent to handle it, and the child to resume via `callr_r_session_muffle` restart.

This is the key insight: **R's condition/restart system IS a pause/resume mechanism**. A tool call becomes a condition signal. The host catches it, executes the tool, and invokes the restart with the result. This is semantically identical to Monty's `start()`/`resume()` pattern, but using R's native exception handling rather than interpreter-level snapshotting.

---

## 2. Strengths

### S1: Full R Language Compatibility
Unlike Monty (which supports a Python subset -- no classes, no match statements, limited stdlib), this approach runs the **real R interpreter**. Every CRAN package, every tidyverse function, every R idiom works. LLMs already know R; they don't need to learn a restricted subset.

### S2: Battle-Tested Infrastructure
- `callr` has been on CRAN since 2016, with 3.7.6 released July 2025. It's maintained by the r-lib team (Posit).
- `processx` provides the IPC layer -- also mature, well-tested across platforms.
- Posit owns both packages and can modify internals if needed.

### S3: Posit's Home Turf
Posit built callr, processx, and ellmer. They understand these internals deeply. Extending callr with first-class pause/resume support for tool calls is a natural evolution, not a foreign integration.

### S4: Fast Startup, Low Overhead
- R subprocess boots in 100-300ms (vs Docker at ~195ms, Pyodide at ~2800ms)
- Pre-warmed sessions are instant -- the R process is already running and waiting
- No container image layers, no WASM compilation, no network round-trips to cloud services

### S5: OS Sandbox Is Proven
- Anthropic's `sandbox-runtime` (open source) already implements this exact pattern: Seatbelt on macOS, bubblewrap on Linux, with proxy-based network filtering
- Google's nsjail, Chromium's sandbox, and Cloudflare's seccomp tools demonstrate the approach at scale
- Claude Code itself uses Seatbelt sandboxing for its agent execution

### S6: Gradual Adoption Path
The tool can start with just callr (no sandbox) for trusted environments, then layer on OS restrictions incrementally. RAppArmor already exists on CRAN for Linux, providing rlimits and AppArmor integration within R.

### S7: Multi-Session Concurrency
callr's task queue pattern (documented in their vignette) supports pools of pre-warmed R sessions with `processx::poll()` for concurrent monitoring. This enables serving multiple LLM conversations simultaneously.

---

## 3. Weaknesses

### W1: Pause/Resume Requires Custom Implementation
callr doesn't have built-in pause/resume for tool calls today. The condition/restart mechanism *can* be repurposed for this, but it requires:
- A custom condition class (`tool_call_condition`)
- A handler in the parent that reads the condition, executes the tool, and sends the result back
- A restart in the child that receives the result and continues execution
- Careful handling of serialization boundaries (not all R objects cross process boundaries cleanly)

This is maybe 500-1000 lines of new code, but it's novel integration work.

### W2: Sandbox Profiles Are Platform-Specific
- Linux: seccomp-bpf + namespaces + Landlock -- most powerful but Linux-only
- macOS: Seatbelt -- `sandbox-exec` is deprecated (Apple marked it as such), profiles use an undocumented Scheme dialect, and network filtering is all-or-nothing without proxy tricks
- Windows: No native sandbox equivalent -- would need a separate approach entirely

This means maintaining 2-3 platform backends, each with different capability levels.

### W3: R's Escape Hatches
R is a dynamic language with many ways to escape a sandbox:
- `system()`, `system2()`, `processx::process$new()` can spawn arbitrary processes
- `.Call()` and `.C()` invoke compiled code directly
- `readLines(pipe(...))` opens shell pipes
- `download.file()` makes network requests
- Package `.onLoad()` hooks can execute arbitrary code at library load time

The OS sandbox catches these at the syscall level, but the seccomp profile needs to be carefully designed to block dangerous syscalls without breaking R's legitimate needs (R uses fork(), mmap(), many file operations).

### W4: Security Is "Defense in Depth" Not "Provably Safe"
Unlike Monty (which controls the interpreter and can simply not implement dangerous operations), this approach relies on blocking dangerous operations at the OS level. A sufficiently creative attacker might find gaps between allowed syscalls. The security guarantee is practical, not theoretical.

### W5: macOS Seatbelt Fragility
Apple has deprecated `sandbox-exec` and the Seatbelt profile language is undocumented. While it still works (and Anthropic ships it in production), there's risk of Apple removing or changing it in a future macOS release. The macOS story is weaker than the Linux story.

### W6: State Serialization Limitations
Unlike Monty's `dump()`/`load()` which can snapshot the entire interpreter state to bytes, callr cannot serialize a running R session. If the host process crashes mid-tool-call, the execution state is lost. There's no "resume from snapshot" capability.

---

## 4. Implementation Sketch

### Phase 1: Tool Call Protocol (2-3 weeks)

```r
# In the sandboxed R subprocess, registered tool functions look like:
request_tool <- function(tool_name, args) {
  # Signal a condition that the parent will catch
  cond <- structure(
    class = c("tool_call", "condition"),
    list(
      message = paste0("tool_call:", tool_name),
      tool_name = tool_name,
      args = args
    )
  )
  # This blocks until the parent sends back a result
  result <- withCallingHandlers(
    signalCondition(cond),
    tool_result = function(r) invokeRestart("resume_with", r$value)
  )
  result
}

# In the host, the condition handler:
session$call(function() {
  # LLM-generated code that may call tools
  weather <- request_tool("get_weather", list(city = "Boston"))
  paste("The weather is", weather$temp, "degrees")
})

# Host loop:
repeat {
  session$poll_process(timeout = 5000)
  msg <- session$read()
  if (msg$code == 301 && inherits(msg$message, "tool_call")) {
    result <- execute_tool(msg$message$tool_name, msg$message$args)
    session$write_result(result)  # New method needed
  } else if (msg$code == 200) {
    return(msg$result)
  }
}
```

### Phase 2: OS Sandbox Wrapper (2-3 weeks)

Leverage Anthropic's `sandbox-runtime` pattern:

```r
# Launch R session inside sandbox
sandbox_r_session <- function(
  allowed_packages = c("base", "stats", "utils"),
  network = FALSE,
  writable_paths = character()
) {
  if (.Platform$OS.type == "unix") {
    if (Sys.info()["sysname"] == "Linux") {
      # Use bubblewrap + seccomp
      sandbox_cmd <- build_bwrap_command(writable_paths, network)
    } else {
      # Use sandbox-exec with Seatbelt profile
      profile <- generate_seatbelt_profile(writable_paths, network)
      sandbox_cmd <- paste("sandbox-exec -f", profile)
    }
  }
  # Start callr session within sandbox
  callr::r_session$new(
    options = callr::r_session_options(
      env = c(R_LIBS_USER = allowed_packages_path),
      cmdargs = c("--vanilla", "--no-save")
    )
  )
}
```

### Phase 3: ellmer Integration (1-2 weeks)

Wire it into ellmer's tool calling framework:

```r
chat <- ellmer::chat_openai(model = "gpt-4o")
chat$register_tool(
  tool("get_weather", "Get weather for a city", city = type_string()),
  function(city) { jsonlite::toJSON(list(temp = 72, condition = "sunny")) }
)

# LLM writes R code that calls tools
chat$chat("Write R code to get the weather in Boston and plot it")
# -> LLM generates code -> sandboxed R executes -> tool calls pause/resume
```

### Phase 4: Resource Limits & Monitoring (1 week)

```r
# Via RAppArmor on Linux or processx on all platforms:
# - CPU time limit (RLIMIT_CPU)
# - Memory limit (RLIMIT_AS)
# - File size limit (RLIMIT_FSIZE)
# - No child process spawning (RLIMIT_NPROC = 0)
# - Execution timeout via processx::poll() timeout
```

---

## 5. Comparison to Monty's Architecture

| Dimension | Monty (Python/Rust) | Approach A (callr + OS sandbox) |
|-----------|--------------------|---------------------------------|
| Language coverage | Python subset (no classes, limited stdlib) | Full R language + all CRAN packages |
| Startup time | <0.1ms | 100-300ms (pre-warmed: ~0ms) |
| Pause/resume | Native interpreter feature | Condition/restart system (to be built) |
| State serialization | dump()/load() to bytes | Not supported |
| Security model | No dangerous ops implemented | OS-level syscall blocking |
| Third-party packages | None supported | Full CRAN access (controlled) |
| Implementation effort | Multi-year (rewrite interpreter) | Months (extend existing tools) |
| Runtime performance | ~CPython speed | Native R speed |

---

## 6. Risk Assessment

**Low risk**: callr/processx stability, R subprocess management, basic sandboxing on Linux
**Medium risk**: Pause/resume protocol implementation, cross-platform sandbox parity, seccomp profile tuning for R's needs
**High risk**: macOS Seatbelt deprecation, Windows support, security of allowing full R language in sandbox

---

## 7. Why This Is the Right Approach for Posit

1. **Time to market**: This can ship in months, not years. The building blocks exist.
2. **R ecosystem leverage**: LLMs can use tidyverse, ggplot2, data.table -- the packages that make R valuable. A restricted subset defeats the purpose.
3. **Posit owns the stack**: callr, processx, ellmer, R itself -- Posit can make any upstream changes needed.
4. **Proven pattern**: Anthropic ships this exact architecture (OS sandbox + subprocess) in Claude Code today.
5. **Incremental deployment**: Start without sandbox for trusted environments, add security layers progressively.

The fundamental insight is that R is too large and dynamic to rewrite (the Monty approach), but the process boundary is a well-understood security primitive. By combining Posit's excellent subprocess tooling with modern OS sandboxing, we get 90% of Monty's safety guarantees with 100% R compatibility, at a fraction of the implementation cost.
