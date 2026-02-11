# Apply Windows Job Object limits to a process

Generates and executes a PowerShell script that uses C# P/Invoke to
create a Job Object with the specified resource limits and assign the
target process to it.

## Usage

``` r
apply_windows_job_object(pid, limits)
```

## Arguments

- pid:

  Integer process ID to constrain

- limits:

  Named list of supported limits (cpu, memory, nproc)

## Value

Invisible `NULL`. Warns on failure (best-effort).
