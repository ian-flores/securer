# securer: run LLM-written R code in a sandbox

securer runs R code in a child R process inside an OS sandbox. The code
can call tools, which are functions that run in your own session: the
child pauses, your session runs the tool, and the child carries on with
the result.

Start with:

- [`execute_r()`](https://ian-flores.github.io/securer/reference/execute_r.md)
  to run one piece of code and shut the session down.

- [SecureSession](https://ian-flores.github.io/securer/reference/SecureSession.md)
  to keep a session open across many calls.

- [`securer_tool()`](https://ian-flores.github.io/securer/reference/securer_tool.md)
  to define the tools the code can call.

## See also

Useful links:

- <https://ian-flores.github.io/securer/>

- <https://github.com/ian-flores/securer>

- Report bugs at <https://github.com/ian-flores/securer/issues>

## Author

**Maintainer**: Ian Flores Siaca <iflores.siaca@hey.com> \[copyright
holder\]
