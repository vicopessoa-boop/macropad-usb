' Inicia o Macropad USB sem janela. O log fica em macropad.log, na mesma pasta.
' Se o programa ja estiver rodando, nao abre outro.
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
If wmi.ExecQuery("SELECT * FROM Win32_Process WHERE Name='macropad.exe'").Count > 0 Then WScript.Quit

Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = dir
sh.Run """" & dir & "\macropad.exe"" -config """ & dir & "\config.json"" -log """ & dir & "\macropad.log""", 0, False
