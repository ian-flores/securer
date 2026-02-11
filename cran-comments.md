## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

- macOS (latest), R release
- Ubuntu (latest), R release
- Ubuntu (latest), R devel
- Ubuntu (latest), R oldrel-1
- Windows (latest), R release

## Notes

This package optionally uses platform-specific sandbox tools:
- **Linux**: bubblewrap (`bwrap`) for namespace isolation
- **macOS**: `sandbox-exec` (included with macOS)
- **Windows**: PowerShell (included with Windows) for Job Object resource limits

All sandbox features are optional and the package functions correctly
without them by using `sandbox = FALSE`.
