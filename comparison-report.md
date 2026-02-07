# Safe R Code Execution for LLM Agents: Approach Comparison Report

## Approaches Compared

- **Approach A**: callr + OS sandbox (local subprocess with seccomp/Seatbelt)
- **Approach D**: Posit Connect backend (enterprise execution infrastructure)

Inspired by Pydantic's [Monty project](https://github.com/pydantic/monty) -- a minimal, secure Python interpreter in Rust with pause/resume for external function calls. We can't rewrite R in Rust, but we can copy the architectural patterns.

---

## 1. Executive Summary

Both approaches run the real R interpreter with full CRAN package access. Neither proposes a restricted R subset (the Monty path is infeasible for R). The fundamental disagreement is about **where the security boundary lives**: at the OS process boundary on the user's machine (A) or at the network boundary to a managed server (D).

**Recommendation**: Build Approach A as the default local backend, with Approach D available as an enterprise option. The pause/resume architecture (A's core innovation) must work locally first; Connect integration is a deployment target, not an execution architecture.

---

## 2. Architecture Comparison

### Approach A: callr + OS Sandbox

```
User's Machine
  |
  Host Process (R/Python running ellmer)
  |
  +-- callr::r_session (pre-warmed R subprocess)
  |     |-- IPC via fd3 pipe (processx)
  |     |-- Condition/restart system for pause/resume
  |     +-- poll()/read() for async monitoring
  |
  +-- OS Sandbox Layer
        |-- Linux: seccomp-bpf + namespaces + Landlock
        |-- macOS: sandbox-exec with Seatbelt profiles
        +-- Network: proxy-based filtering
```

**Key mechanism**: R's condition/restart system repurposed as pause/resume. When LLM code calls a registered tool, it signals a condition (code 301 via fd3). The host catches it, executes the tool locally, and invokes a restart with the result. Execution continues in the same R process with full state preserved.

### Approach D: Posit Connect Backend

```
User's Machine                    Connect Server (Linux)
  |                                |
  ellmer Chat object               Plumber API
  |                                |  +-- eval(parse(text=code))
  +-- HTTP POST /run  ---------->  |  +-- Namespace isolation
  |                                |  +-- Privilege separation
  <-- JSON response  <----------   |  +-- Resource limits
                                   +-- Process pooling
```

**Key mechanism**: HTTP request/response. LLM-generated code is sent to a pre-deployed Plumber API on Connect, which evaluates it in a sandboxed process and returns results as JSON. Connect's existing namespace isolation (CLONE_NEWNS, CLONE_NEWUSER), RunAs user separation, and resource limits provide the security layer.

---

## 3. Dimension-by-Dimension Analysis

### 3.1 Pause/Resume for Tool Calls

This is the architectural crux. Monty's defining feature is that LLM-generated code can call external functions (tools), pausing execution mid-stream while the host fulfills the request, then resuming with the result. This collapses multiple LLM round-trips into a single code generation.

| | Approach A | Approach D |
|---|---|---|
| **Mechanism** | R condition/restart system over fd3 IPC | No native mechanism |
| **Latency per tool call** | ~0.1ms (IPC) | ~100-200ms (HTTP round-trip, warm) |
| **5 tool calls in one script** | ~0.5ms overhead | ~500-1000ms overhead |
| **State preservation** | Full -- same R process, same environment | Fragile -- requires server-side session state or code splitting |
| **Tool execution location** | Host machine (access to local resources) | Connect server (no access to local resources) |

**Verdict**: Approach A wins decisively. The condition/restart mechanism is a natural fit for pause/resume and keeps tool execution local. Approach D would require building WebSocket-based bidirectional communication on top of HTTP on top of Connect's process model to achieve the same effect -- essentially reimplementing IPC over the network.

**Approach D's counter-argument**: For simple execute-and-return workflows (no mid-stream tool calls), the HTTP model is simpler. Not all LLM code execution needs pause/resume -- sometimes you just want to run a snippet and get results back.

**Assessment**: True, but the pause/resume pattern is the *entire point* of code mode. Without it, you're just running code remotely -- useful, but not the Monty-inspired architecture Posit is targeting.

### 3.2 Security

| | Approach A | Approach D |
|---|---|---|
| **Security primitives** | seccomp-bpf, namespaces, Landlock (Linux); Seatbelt (macOS) | Connect's namespace isolation, RunAs, rlimits |
| **Underlying technology** | Same Linux kernel features | Same Linux kernel features (via Connect) |
| **Threat model** | Adversarial code vs. host | Publisher isolation (multi-tenant) |
| **Configuration** | New profiles to build and maintain | 10+ years of production refinement |
| **Attack surface** | R's dynamic nature creates many escape vectors at language level; OS sandbox blocks at syscall level | Same R escape vectors exist; Connect's namespace provides the boundary |
| **Platform coverage** | Linux (strong), macOS (fragile/deprecated), Windows (none) | Linux only (server-side); all client platforms |

**Approach A's vulnerability**: R's dynamic nature (eval, .Call, .Internal, NSE, Rcpp inline compilation) creates a combinatorially explosive escape surface. The OS sandbox must block dangerous syscalls without breaking R's legitimate needs -- fork() for parallel processing, socket() for HTTP packages, execve() for package compilation. This is an ongoing arms race, not a one-time configuration.

**Approach D's vulnerability**: Connect's sandbox was designed for publisher isolation (protecting tenants from each other), not for adversarial code containment (protecting the host from malicious LLM output). These are different threat models. Additionally, Connect runs code with more privilege than strictly necessary for LLM snippet execution.

**Approach D's counter-argument**: The 2025 CVEs against GitHub Copilot (CVE-2025-53773) and Cursor IDE (CVE-2025-54135) demonstrate that local code execution sandboxes are active attack targets. Connect's network boundary adds a layer that local sandboxes lack.

**Assessment**: Both approaches use the same underlying Linux primitives. Connect's advantage is operational maturity and configuration refinement. Approach A's advantage is a tighter, purpose-built sandbox. Neither is "provably safe." The honest answer is defense-in-depth: local OS sandbox (A) PLUS network isolation (D) for production deployments.

### 3.3 Platform Support

| | Approach A | Approach D |
|---|---|---|
| **Linux** | Excellent (seccomp + namespaces + Landlock) | Excellent (server-side) |
| **macOS** | Fragile (Seatbelt deprecated, undocumented profile language) | N/A (client makes HTTP calls) |
| **Windows** | No story | N/A (client makes HTTP calls) |
| **Client requirements** | OS-specific sandbox tools (bubblewrap, sandbox-exec) | Just HTTP (httr2) |

**Verdict**: Approach D wins on cross-platform client support. Approach A's macOS story is genuinely concerning -- Apple deprecated sandbox-exec and provides no replacement for command-line process sandboxing. However, Anthropic ships Seatbelt in Claude Code today, proving it works in practice despite the deprecation risk.

**Nuance**: Approach A without the OS sandbox layer (just callr with rlimits) works on all platforms. The sandbox provides defense-in-depth, not the core functionality. A tiered model -- basic rlimits everywhere, full sandbox on Linux, Seatbelt on macOS where available -- is viable.

### 3.4 Latency and Performance

| | Approach A | Approach D |
|---|---|---|
| **Cold start** | 100-300ms (R boot) | 5-30 seconds (process start + package load) |
| **Warm start** | ~0ms (pre-warmed session) | 50-200ms (HTTP round-trip) |
| **Per-tool-call overhead** | ~0.1ms (IPC) | 100-200ms (HTTP) |
| **Memory per session** | 50-100MB (base R); 500MB+ with tidyverse | Managed by Connect's process pooler |

**Approach D's counter-argument**: LLM inference takes 1-10 seconds per turn. The difference between 0.1ms and 200ms per tool call is "invisible to the user." This is true for single tool calls but false for code mode with 5-10 tool calls per script -- where A adds 0.5ms total and D adds 1-2 seconds.

**Assessment**: Latency matters for code mode (multiple tool calls per execution). For simple execute-and-return, both are acceptable. Pre-warmed sessions solve cold start for both approaches, though Connect's process management is more mature.

### 3.5 Infrastructure Requirements

| | Approach A | Approach D |
|---|---|---|
| **Server required** | No | Yes (Connect or Connect Cloud) |
| **Cost** | Free (open source) | Enterprise license ($$$) or Cloud subscription |
| **Offline support** | Yes | No |
| **Setup complexity** | Install R package + OS sandbox tools | Deploy Connect + configure Plumber API |

**Verdict**: Approach A wins for accessibility. Approach D wins for managed operations.

**The paywall problem**: If code mode requires Connect, it becomes a paid feature. The open-source R community -- R's largest constituency -- would be excluded. Monty is open source. Claude Code's sandbox-runtime is open source. The industry norm is free local execution.

**Approach D's counter-argument**: Connect Cloud has a free tier. And users already need internet to call LLM APIs, so requiring a server isn't adding a new dependency class.

**Assessment**: The free tier is limited (public GitHub repos, constrained compute). And there's a categorical difference between "needs internet to call an API" and "needs internet to run my own code." R users expect local execution. A Connect-only approach would face significant community resistance.

### 3.6 Implementation Effort

| | Approach A | Approach D |
|---|---|---|
| **New code** | ~1000 lines (tool protocol + sandbox wrappers) | ~800 lines (Plumber API + ellmer client) |
| **Time estimate** | 6-8 weeks | 2-3 weeks (without pause/resume) |
| **Ongoing maintenance** | Seccomp/Seatbelt profile tuning, platform testing | Plumber API versioning, Connect compatibility |
| **Security audit needed** | Yes (new sandbox) | Leverages Connect's existing audits |

**Assessment**: Approach D is faster to ship for the simple execute-and-return case. Approach A requires more upfront investment but delivers the architecturally superior pause/resume model. If pause/resume is added to D via WebSockets, the implementation effort converges.

### 3.7 Ecosystem and Strategic Fit

| | Approach A | Approach D |
|---|---|---|
| **Open source alignment** | Strong (callr, processx are open source) | Weak (requires proprietary Connect) |
| **Posit business model** | Doesn't drive revenue directly | Drives Connect adoption and upsell |
| **Community adoption** | Anyone can use it | Limited to Connect customers |
| **Competitive moat** | Technique is replicable | Connect integration is proprietary |

**Assessment**: This is the classic open-source-company tension. Approach A serves the community. Approach D serves the business. The right answer serves both: open-source local execution (A) with premium Connect integration (D).

---

## 4. Areas of Agreement

Both advocates agreed on several key points:

1. **R cannot be rewritten** -- A Monty-for-R (minimal R interpreter in Rust) is infeasible. R's core (S3/S4 dispatch, NSE, formula objects, ALTREP, environments-as-first-class) is too complex and intertwined.

2. **Full CRAN access is essential** -- LLMs generate code using tidyverse, ggplot2, data.table. A restricted package set defeats the purpose.

3. **Both approaches should coexist** -- Both advocates converged on a tiered architecture with local (A) and server (D) backends. The disagreement was about which is the default.

4. **The threat is real** -- LLM-generated code is an active attack surface (OWASP #1 for AI, real CVEs in 2025). Safety cannot be optional.

5. **Posit's existing tools are the right building blocks** -- callr, processx, ellmer, Connect are all Posit-maintained. No third-party dependencies needed for either approach.

---

## 5. The Key Disagreements

### Default posture: Secure-by-default vs. accessible-by-default

**Approach D**: The default should be Connect (secure). Local execution should be opt-in with explicit risk acknowledgment.

**Approach A**: The default should be local (accessible). Connect should be opt-in for enterprise deployments.

**Resolution**: The default should be local with best-available sandboxing. On Linux, that means seccomp + namespaces. On macOS, Seatbelt. On Windows, rlimits only (with a warning). Connect is the recommended production backend. This follows the pattern of every major development tool: local by default, server for production.

### Pause/resume: Essential or nice-to-have?

**Approach A**: Pause/resume is the core innovation of code mode. Without it, you're just running code remotely.

**Approach D**: Simple execute-and-return covers most use cases. Pause/resume can be added later.

**Resolution**: Pause/resume is what distinguishes code mode from a Jupyter kernel. It's what Monty was built for. It should be the target architecture, even if the first release supports only simple execution. Approach A's condition/restart mechanism is the natural implementation path.

### Security adequacy: Is OS-level sandboxing enough?

**Approach D**: R's escape surface is too large for syscall-level blocking. The arms race is unwinnable.

**Approach A**: The same Linux primitives underlie both approaches. Connect's advantage is configuration maturity, not fundamentally different technology.

**Resolution**: Both are right. OS-level sandboxing is necessary but may not be sufficient against sophisticated attacks. Connect adds operational maturity. The best security posture combines both: local sandbox for defense-in-depth, Connect for adversarial production environments. Neither alone is complete.

---

## 6. Recommended Architecture

```
ellmer::code_mode()
    |
    +-- Backend Interface (abstract)
    |     $execute(code, tools, timeout)
    |     $supports_pause_resume()
    |
    +-- LocalBackend (Approach A) -- DEFAULT
    |     callr::r_session inside OS sandbox
    |     Pause/resume via condition/restart IPC
    |     Works offline, no infrastructure
    |     Security: OS sandbox + rlimits
    |     Platforms: Linux (full), macOS (Seatbelt), Windows (rlimits only)
    |
    +-- ConnectBackend (Approach D) -- ENTERPRISE OPTION
          HTTP to pre-deployed Plumber executor
          Session state management on server
          Security: Connect namespace isolation + audit logging
          Scaling: Connect process pooling + Kubernetes
          Platforms: Any client (server runs on Linux)
```

### Implementation Roadmap

**Phase 1 (Weeks 1-3): Core Protocol**
- Define the tool call protocol (condition class, message format, restart mechanism)
- Implement in callr with basic rlimits (no OS sandbox yet)
- Works on all platforms immediately
- Ship as `ellmer::code_mode(backend = "local")`

**Phase 2 (Weeks 4-6): OS Sandbox**
- Add seccomp + namespace sandbox on Linux (reference: Anthropic's srt, Google's nsjail)
- Add Seatbelt sandbox on macOS (reference: Anthropic's sandbox-runtime)
- Windows: rlimits only with documentation of limitations

**Phase 3 (Weeks 7-8): Connect Backend**
- Build Plumber executor API for Connect
- Add `ellmer::code_mode(backend = "connect", url = "...")`
- Simple execute-and-return initially; WebSocket pause/resume later

**Phase 4 (Weeks 9-12): Hardening**
- Security audit of sandbox profiles
- Performance benchmarking and session pool tuning
- Documentation and CRAN submission

---

## 7. Decision Matrix

| Criterion | Weight | Approach A Score | Approach D Score | Notes |
|-----------|--------|-----------------|-----------------|-------|
| Pause/resume support | 25% | 9/10 | 3/10 | A's condition/restart is natural; D requires building IPC over HTTP |
| Security | 20% | 6/10 | 8/10 | Both use OS primitives; D has operational maturity |
| Platform support | 15% | 5/10 | 8/10 | D avoids client-side platform fragmentation |
| Accessibility (no paywall) | 15% | 10/10 | 4/10 | A is free; D requires Connect license/Cloud |
| Latency | 10% | 9/10 | 6/10 | Matters for multi-tool code mode |
| Implementation effort | 10% | 6/10 | 8/10 | D is faster to ship (without pause/resume) |
| Offline support | 5% | 10/10 | 0/10 | A works offline; D requires network |
| **Weighted Total** | **100%** | **7.5/10** | **5.8/10** | |

---

## 8. Conclusion

**Approach A (callr + OS sandbox) should be the primary architecture** because it delivers the core innovation (pause/resume for tool calls), works locally without infrastructure, serves the broadest user base, and aligns with the open-source R ecosystem's values.

**Approach D (Connect backend) should be the enterprise option** because it provides superior operational security, eliminates platform fragmentation, and creates a natural business driver for Posit's commercial products.

The approaches are complementary, not competing. Build A first (it's the foundation), add D as a deployment target (it's the enterprise story). Together they cover individual developers, academic researchers, and enterprise data science teams -- all of Posit's constituencies.

The worst outcome would be building D alone, which would paywall code execution safety and alienate the open-source community. The second-worst would be building A alone without ever offering a Connect backend, which would leave enterprise customers without a managed, auditable execution environment.

Build both. Ship A first.

---

## Sources

### callr and processx
- [callr CRAN documentation (v3.7.6)](https://cran.r-project.org/web/packages/callr/callr.pdf)
- [r_session reference](https://callr.r-lib.org/reference/r_session.html)
- [Persistent R Sessions vignette](https://callr.r-lib.org/articles/r-session.html)
- [Task queue with callr](https://callr.r-lib.org/articles/Task-queue-with-callr.html)
- [processx internals](https://processx.r-lib.org/articles/internals.html)
- [callr GitHub](https://github.com/r-lib/callr)

### Pydantic Monty
- [Monty GitHub](https://github.com/pydantic/monty)
- [Pydantic AI tools documentation](https://ai.pydantic.dev/tools/)
- [Deferred tools](https://ai.pydantic.dev/deferred-tools/)

### OS Sandboxing
- [Anthropic sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
- [Claude Code sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)
- [Google nsjail](https://github.com/google/nsjail)
- [seccomp BPF kernel docs](https://www.kernel.org/doc/html/v4.19/userspace-api/seccomp_filter.html)
- [Pierce Freeman: Deep dive on agent sandboxes](https://pierce.dev/notes/a-deep-dive-on-agent-sandboxes)
- [Cloudflare seccomp sandbox](https://github.com/cloudflare/sandbox)

### R Sandboxing
- [RAppArmor (CRAN)](https://cran.r-project.org/package=RAppArmor)
- [learnr safe() function](https://rstudio.github.io/learnr/reference/safe.html)
- [sandbox R package](https://github.com/thebioengineer/sandbox)
- [Evaluating R code from malicious sources](https://coolbutuseless.github.io/2018/02/12/part-3-evaluating-r-code-from-potentially-malicious-sources/)

### Posit Connect
- [Connect process management](https://docs.posit.co/connect/admin/process-management/)
- [Connect security](https://docs.posit.co/connect/admin/security/)
- [Connect configuration](https://docs.posit.co/connect/admin/appendix/configuration/)
- [Connect Cloud plans](https://docs.posit.co/connect-cloud/user/account/plans.html)

### Posit ellmer
- [ellmer documentation](https://ellmer.tidyverse.org/)
- [ellmer GitHub](https://github.com/tidyverse/ellmer)
- [Tool calls with ellmer](https://posit.co/blog/easy-tool-calls-with-ellmer-and-chatlas/)

### Python Sandboxing (for comparison)
- [snekbox (nsjail + Python)](https://github.com/python-discord/snekbox)
- [PythonSafeEval](https://github.com/s3131212/PythonSafeEval)
- [codejail (AppArmor)](https://github.com/openedx/codejail)

### macOS Seatbelt
- [sandbox-exec overview](https://igorstechnoclub.com/sandbox-exec/)
- [macOS sandbox-exec quick glance](https://jmmv.dev/2019/11/macos-sandbox-exec.html)
- [Seatbelt profile reference](https://gist.github.com/n8henrie/eaaa1a25753fadbd7715e85a38b99831)
