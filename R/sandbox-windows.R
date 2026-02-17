#' Build Windows sandbox configuration
#'
#' Provides environment isolation and optional resource limits via Windows
#' Job Objects.  Environment isolation creates a sanitized set of environment
#' variables with clean HOME, TMPDIR, TMP, TEMP pointing to a private temp
#' directory, and an empty R_LIBS_USER.
#'
#' When resource limits are provided (cpu, memory, nproc), a PowerShell
#' script using C# P/Invoke is generated to create a Job Object with the
#' specified constraints and assign the child process to it.  Limits that
#' have no Job Object equivalent (fsize, nofile, stack) emit a warning and
#' are skipped.
#'
#' @param socket_path Path to the UDS socket
#' @param r_home      Path to the R installation
#' @param limits      Optional named list of resource limits.  Supported on
#'   Windows via Job Objects: `cpu`, `memory`, `nproc`.  Unsupported (will
#'   warn): `fsize`, `nofile`, `stack`.
#' @return A list with elements:
#'   \describe{
#'     \item{wrapper}{Always `NULL` on Windows (no wrapper script)}
#'     \item{profile_path}{Always `NULL` on Windows}
#'     \item{env}{A named character vector of sanitized environment variables}
#'     \item{sandbox_tmp}{Path to the private temp directory}
#'     \item{apply_limits}{A function taking a PID to apply Job Object limits,
#'       or `NULL` if no supported limits were requested}
#'   }
#' @keywords internal
build_sandbox_windows <- function(socket_path, r_home, limits = NULL) {
  message(
    "Note: Windows sandbox provides environment isolation only -- ",
    "no filesystem or network restrictions. See ?SecureSession for details."
  )

  # Create a private temp directory for the sandboxed session
  sandbox_tmp <- tempfile("securer_win_")
  dir.create(sandbox_tmp, recursive = TRUE)

  # Build sanitized environment
  env <- c(
    HOME        = sandbox_tmp,
    TMPDIR      = sandbox_tmp,
    TMP         = sandbox_tmp,
    TEMP        = sandbox_tmp,
    R_LIBS_USER = ""
  )

  # Determine which limits are supported and which are not
  apply_limits_fn <- NULL

  if (!is.null(limits) && length(limits) > 0) {
    unsupported <- c("fsize", "nofile", "stack")
    unsupported_present <- intersect(names(limits), unsupported)
    for (lim_name in unsupported_present) {
      warning(
        sprintf("Resource limit '%s' is not supported on Windows and will be skipped", lim_name),
        call. = FALSE
      )
    }

    supported <- intersect(names(limits), windows_supported_limits())
    if (length(supported) > 0) {
      # Build the apply_limits function that creates a Job Object via PowerShell
      supported_limits <- limits[supported]
      apply_limits_fn <- function(pid) {
        apply_windows_job_object(pid, supported_limits)
      }
    }
  }

  list(
    wrapper      = NULL,
    profile_path = NULL,
    env          = env,
    sandbox_tmp  = sandbox_tmp,
    apply_limits = apply_limits_fn
  )
}

#' Apply Windows Job Object limits to a process
#'
#' Generates and executes a PowerShell script that uses C# P/Invoke to
#' create a Job Object with the specified resource limits and assign the
#' target process to it.
#'
#' @param pid Integer process ID to constrain
#' @param limits Named list of supported limits (cpu, memory, nproc)
#' @return Invisible `NULL`.  Warns on failure (best-effort).
#' @keywords internal
apply_windows_job_object <- function(pid, limits) {
  # Build the C# limit-setting code
  limit_flags <- "0x00002000"  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
  limit_assignments <- character(0)

  if (!is.null(limits$memory)) {
    limit_flags <- paste(limit_flags, "0x00000100", sep = " | ")
    # JOB_OBJECT_LIMIT_PROCESS_MEMORY
    limit_assignments <- c(
      limit_assignments,
      sprintf("extInfo.ProcessMemoryLimit = (UIntPtr)%s;",
              format(as.integer(limits$memory), scientific = FALSE))
    )
  }

  if (!is.null(limits$cpu)) {
    limit_flags <- paste(limit_flags, "0x00000004", sep = " | ")
    # JOB_OBJECT_LIMIT_PROCESS_TIME - PerProcessUserTimeLimit in 100ns units
    cpu_100ns <- as.numeric(limits$cpu) * 10000000
    limit_assignments <- c(
      limit_assignments,
      sprintf("extInfo.BasicLimitInformation.PerProcessUserTimeLimit = %s;",
              format(cpu_100ns, scientific = FALSE))
    )
  }

  if (!is.null(limits$nproc)) {
    limit_flags <- paste(limit_flags, "0x00000008", sep = " | ")
    # JOB_OBJECT_LIMIT_ACTIVE_PROCESS
    limit_assignments <- c(
      limit_assignments,
      sprintf("extInfo.BasicLimitInformation.ActiveProcessLimit = %d;",
              as.integer(limits$nproc))
    )
  }

  limit_assignments_str <- paste(limit_assignments, collapse = "\n                ")

  ps1_code <- sprintf('
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class JobObjectHelper {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(
        IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    public static int Apply(uint pid) {
        IntPtr hJob = CreateJobObjectW(IntPtr.Zero, null);
        if (hJob == IntPtr.Zero) return 1;

        var extInfo = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        extInfo.BasicLimitInformation.LimitFlags = %s;
                %s

        int size = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        Marshal.StructureToPtr(extInfo, ptr, false);

        // JobObjectExtendedLimitInformation = 9
        bool setOk = SetInformationJobObject(hJob, 9, ptr, (uint)size);
        Marshal.FreeHGlobal(ptr);
        if (!setOk) { CloseHandle(hJob); return 2; }

        // PROCESS_SET_QUOTA | PROCESS_TERMINATE = 0x0100 | 0x0001
        IntPtr hProcess = OpenProcess(0x0101, false, pid);
        if (hProcess == IntPtr.Zero) { CloseHandle(hJob); return 3; }

        bool assignOk = AssignProcessToJobObject(hJob, hProcess);
        CloseHandle(hProcess);
        // Do NOT close hJob - it must stay open for limits to remain in effect
        if (!assignOk) { CloseHandle(hJob); return 4; }

        return 0;
    }
}
"@

exit [JobObjectHelper]::Apply(%d)
', limit_flags, limit_assignments_str, as.integer(pid))

  # Write the script to a temp file and execute it
  ps1_path <- tempfile("securer_job_", fileext = ".ps1")
  on.exit(unlink(ps1_path), add = TRUE)
  writeLines(ps1_code, ps1_path)

  result <- tryCatch({
    processx::run(
      "powershell",
      args = c(
        "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", ps1_path
      ),
      timeout = 10,
      error_on_status = FALSE
    )
  }, error = function(e) {
    list(status = -1L, stderr = conditionMessage(e))
  })

  if (!identical(result$status, 0L)) {
    warning(
      sprintf(
        "Failed to apply Windows Job Object limits (exit code %s): %s",
        result$status,
        trimws(paste(result$stderr, collapse = " "))
      ),
      call. = FALSE
    )
  }

  invisible(NULL)
}
