' Run the daily monitor in a hidden console using an explicit command interpreter.
Option Explicit
Dim shell, fileSystem, processEnvironment, runtimeParent, runtimeDirectory
Dim monitorPath, commandLine, monitorExit
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")
If WScript.Arguments.Count <> 0 Then WScript.Quit 64
runtimeParent = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Dotfiles"
If Not fileSystem.FolderExists(runtimeParent) Then fileSystem.CreateFolder runtimeParent
runtimeDirectory = fileSystem.BuildPath(runtimeParent, "PsmuxDaily")
If Not fileSystem.FolderExists(runtimeDirectory) Then fileSystem.CreateFolder runtimeDirectory
If fileSystem.FileExists(runtimeDirectory & "\stop.request") Then WScript.Quit 75
Set processEnvironment = shell.Environment("PROCESS")
processEnvironment("DAILY_RUNTIME_DIRECTORY") = runtimeDirectory
processEnvironment("DAILY_RUN_NAME") = "main"
monitorPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "monitor.bat")
commandLine = Quote(shell.ExpandEnvironmentStrings("%ComSpec%")) & " /d /s /c " & Chr(34) & Quote(monitorPath) & Chr(34)
monitorExit = shell.Run(commandLine, 0, True)
WScript.Quit monitorExit

' Return a quoted filesystem argument for the Windows command line.
Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
