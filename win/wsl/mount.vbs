Set objShell = CreateObject("WScript.Shell")
objShell.Run "cmd /c wsl.exe --mount \\.\PHYSICALDRIVE0 --type ext4 >nul 2>&1", 0, True
