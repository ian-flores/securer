# securer: Secure R Code Execution with Tool-Call IPC

Wraps
[`callr::r_session`](https://callr.r-lib.org/reference/r_session.html)
with a bidirectional IPC protocol for pause/resume tool calls, enabling
safe execution of LLM-generated R code inside an OS-level sandbox.

The main entry points are:

- [`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
  – convenience function for one-shot execution

- [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
  – R6 class for persistent sessions with tool support

- [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  – define tools that child code can call

## See also

Useful links:

- <https://github.com/ian-flores/securer>

- Report bugs at <https://github.com/ian-flores/securer/issues>

## Author

**Maintainer**: Ian Flores Siaca <iflores.siaca@hey.com>
