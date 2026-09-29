' Starts the normal checked desktop launcher without a console window.
' A failed import still produces a visible message instead of hanging at PAUSE.
Option Explicit

Dim fso, shell, root, launcher, engine, engineName, result
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
launcher = fso.BuildPath(root, "tools\launch.cmd")

If Not fso.FileExists(launcher) Then
    MsgBox "Hoshi launcher was not found: " & launcher, vbExclamation, "Hoshi"
    WScript.Quit 1
End If

engine = shell.ExpandEnvironmentStrings("%GODOT_EXE%")
If engine = "%GODOT_EXE%" Then engine = ""
If engine = "" And fso.FileExists(fso.BuildPath(root, "godot_path.txt")) Then
    Dim pathFile
    Set pathFile = fso.OpenTextFile(fso.BuildPath(root, "godot_path.txt"), 1)
    engine = Trim(pathFile.ReadLine)
    pathFile.Close
End If

If engine <> "" Then
    engineName = fso.GetFileName(engine)
    If AlreadyRunning(root, engineName) Then WScript.Quit 0
End If

shell.Environment("PROCESS")("HOSHI_LAUNCH_QUIET") = "1"
result = shell.Run(Chr(34) & launcher & Chr(34) & " desktop", 0, True)
If result <> 0 Then
    MsgBox "Hoshi could not start. Check logs\import.log in the project folder.", vbExclamation, "Hoshi"
End If
WScript.Quit result

Function AlreadyRunning(projectRoot, executableName)
    Dim service, processes, process, commandLine
    AlreadyRunning = False
    On Error Resume Next
    Set service = GetObject("winmgmts:\\.\root\cimv2")
    Set processes = service.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE Name='" & Replace(executableName, "'", "''") & "'")
    If Err.Number = 0 Then
        For Each process In processes
            If Not IsNull(process.CommandLine) Then
                commandLine = CStr(process.CommandLine)
                If InStr(1, commandLine, projectRoot, vbTextCompare) > 0 And _
                   InStr(1, commandLine, "--desktop", vbTextCompare) > 0 Then
                    AlreadyRunning = True
                    Exit For
                End If
            End If
        Next
    End If
    On Error GoTo 0
End Function
