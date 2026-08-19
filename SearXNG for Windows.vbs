' SearXNG for Windows - one-click launcher without a console window.
' Double-click to run (executed by wscript.exe).
' If the server is already running, it just opens the browser and exits.

Option Explicit

Dim shell, fso, appDir, pythonw, webapp, i

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
appDir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = appDir

pythonw = appDir & "\python\pythonw.exe"
webapp = appDir & "\python\Lib\site-packages\searx\webapp.py"

' 1. already running? -> open browser and exit
If isServerUp() Then
    openBrowser()
    WScript.Quit 0
End If

' 2. check the bundled files
If Not fso.FileExists(pythonw) Then
    MsgBox "python\pythonw.exe not found. Please check the installation.", 16, "SearXNG for Windows"
    WScript.Quit 1
End If
If Not fso.FileExists(webapp) Then
    MsgBox "searx\webapp.py not found. Please check the installation.", 16, "SearXNG for Windows"
    WScript.Quit 1
End If

' 3. start the server hidden (bundled pythonw, no console window)
shell.Run """" & pythonw & """ """ & webapp & """", 0, False

' 4. wait until the server responds, then open the browser
For i = 1 To 60
    WScript.Sleep 1000
    If isServerUp() Then Exit For
Next
openBrowser()

WScript.Quit 0

' ---------- helpers ----------

Function isServerUp()
    On Error Resume Next
    Dim http
    Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
    http.Open "GET", "http://127.0.0.1:8888/", False
    http.SetTimeouts 1000, 1000, 1000, 1000
    http.Send
    isServerUp = (http.Status = 200)
    Set http = Nothing
    On Error GoTo 0
End Function

Sub openBrowser()
    On Error Resume Next
    shell.Run """http://localhost:8888"""
    On Error GoTo 0
End Sub
