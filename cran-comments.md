## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

* local macOS (aarch64-apple-darwin), R 4.4.x
* GitHub Actions: ubuntu-latest (R release, R devel), macOS-latest (R release), windows-latest (R release)

## Notes

* Tests that spawn child R processes are skipped on CRAN via `skip_on_cran()` to stay within time limits and avoid resource contention.
* Unix domain sockets are created in `/tmp` rather than `tempdir()` due to the ~104 character path length limit on macOS. Socket directories are created with 0700 permissions and cleaned up on session close, timeout, and GC finalization.
* The package optionally uses system tools (`sandbox-exec` on macOS, `bwrap` on Linux) for OS-level sandboxing. These are declared in SystemRequirements and the package functions correctly without them (sandboxing is gracefully disabled).
