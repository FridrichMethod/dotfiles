# Read-only RedirectionGuard probes run in a disposable process. Enabling a
# mitigation on the caller would change a user's interactive PowerShell.
# Official ABI: ProcessRedirectionTrustPolicy = 16, DWORD flags bit 0 = enforce.
# https://learn.microsoft.com/windows/win32/api/winnt/ne-winnt-process_mitigation_policy
# https://learn.microsoft.com/windows/win32/api/winnt/ns-winnt-process-mitigation-redirection-trust-policy
function Get-DotfilesLinkReadErrors {
    param([string[]]$Paths)

    $result = @{}
    $probePaths = @($Paths | Sort-Object -Unique)
    if (-not $probePaths.Count) { return $result }
    $probe = {
        $ErrorActionPreference = 'Stop'
        [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        try {
            Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Dotfiles {
    public static class LinkProbe {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessMitigationPolicy(int policy, ref uint flags, UIntPtr size);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessMitigationPolicy(IntPtr process, int policy, out uint flags, UIntPtr size);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(string path, uint access, uint share,
            IntPtr security, uint disposition, uint attributes, IntPtr template);
        public static void Enable() {
            uint flags = 1;
            if (!SetProcessMitigationPolicy(16, ref flags, (UIntPtr)4))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (!GetProcessMitigationPolicy(new IntPtr(-1), 16, out flags, (UIntPtr)4))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if ((flags & 1) == 0) throw new InvalidOperationException("RedirectionGuard enforcement is unavailable.");
        }
        public static int ReadError(string path) {
            using (var handle = CreateFile(path, 0x80000000, 7, IntPtr.Zero, 3, 0, IntPtr.Zero))
                return handle.IsInvalid ? Marshal.GetLastWin32Error() : 0;
        }
    }
}
'@
            [Dotfiles.LinkProbe]::Enable()
            $paths = ConvertFrom-Json ([Console]::In.ReadToEnd())
            foreach ($path in $paths) { [Console]::Out.WriteLine([Dotfiles.LinkProbe]::ReadError($path)) }
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            exit 1
        }
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $executable = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $start.FileName = Join-Path $PSHOME $executable
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-EncodedCommand',
            [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe.ToString())))) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Cannot start the RedirectionGuard probe.' }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write((ConvertTo-Json -InputObject $probePaths -Compress))
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            throw 'RedirectionGuard probe timed out.'
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $errors = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Cannot verify symlink trust with RedirectionGuard: $($errors.Trim())"
        }
        $codes = @($output.Trim() -split '\r?\n')
        if ($codes.Count -ne $probePaths.Count) { throw 'Incomplete RedirectionGuard probe output.' }
        for ($index = 0; $index -lt $probePaths.Count; $index++) {
            $code = 0
            if (-not [int]::TryParse($codes[$index], [ref]$code) -or $code -lt 0) {
                throw 'Invalid RedirectionGuard probe output.'
            }
            $result[$probePaths[$index]] = $code
        }
        return $result
    } finally {
        $process.Dispose()
    }
}
