On Error Resume next

If WScript.Arguments.Named.Exists("elevated") = False Then
	'Launch the script again as administrator
	CreateObject("Shell.Application").ShellExecute "wscript.exe", """" & WScript.ScriptFullName & """ /elevated", "", "runas", 1
	WScript.Quit
Else
	'Change the working directory from the system32 folder back to the script's folder.
	Set oShell = CreateObject("WScript.Shell")
	oShell.CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)


   Function RestartWithCScript32(extraargs)
   Dim strCMD, iCount
   strCMD = r32wShell.ExpandEnvironmentStrings("%SYSTEMROOT%") & "\SysWOW64\cscript.exe"
   If NOT r32fso.FileExists(strCMD) Then strCMD = "cscript.exe" 
   strCMD = strCMD & Chr(32) & Wscript.ScriptFullName & Chr(32)
   If Wscript.Arguments.Count > 0 Then
    For iCount = 0 To WScript.Arguments.Count - 1
     if Instr(Wscript.Arguments(iCount), " ") = 0 Then 
      strCMD = strCMD & " " & Wscript.Arguments(iCount) & " "
     Else
      If Instr("/-\", Left(Wscript.Arguments(iCount), 1)) > 0 Then 
       If InStr(WScript.Arguments(iCount),"=") > 0 Then
        strCMD = strCMD & " " & Left(Wscript.Arguments(iCount), Instr(Wscript.Arguments(iCount), "=") ) & """" & Mid(Wscript.Arguments(iCount), Instr(Wscript.Arguments(iCount), "=") + 1) & """ "
       ElseIf Instr(WScript.Arguments(iCount),":") > 0 Then
        strCMD = strCMD & " " & Left(Wscript.Arguments(iCount), Instr(Wscript.Arguments(iCount), ":") ) & """" & Mid(Wscript.Arguments(iCount), Instr(Wscript.Arguments(iCount), ":") + 1) & """ "
       Else
        strCMD = strCMD & " """ & Wscript.Arguments(iCount) & """ "
       End If
      Else
       strCMD = strCMD & " """ & Wscript.Arguments(iCount) & """ "
      End If
     End If
    Next
   End If
   r32wShell.Run strCMD & " " & extraargs, 0, False
   End Function

   Dim r32wShell, r32env1, r32env2, r32iCount
   Dim r32fso
   SET r32fso = CreateObject("Scripting.FileSystemObject")
   Set r32wShell = WScript.CreateObject("WScript.Shell")
   r32env1 = r32wShell.ExpandEnvironmentStrings("%PROCESSOR_ARCHITECTURE%")
   If r32env1 <> "x86" Then ' not running in x86 mode
    For r32iCount = 0 To WScript.Arguments.Count - 1
     r32env2 = r32env2 & WScript.Arguments(r32iCount) & VbCrLf
    Next
    If InStr(r32env2,"restart32") = 0 Then RestartWithCScript32 "restart32" Else MsgBox "Cannot find 32bit version of cscript.exe or unknown OS type " & r32env1
    Set r32wShell = Nothing
    WScript.Quit
   End If
   Set r32wShell = Nothing
   Set r32fso = Nothing

End If
Const BTNOK        = 0
Const BTNOKCANCEL  = 1
Const ICONSTOP     = 16
Const ICONQUESTION = 32
Const ICONBANG     = 48
Const ICONINFO     = 64
Const BTNDEFAULT2  = 256
Const IBTNOK       = 1
Const IBTNCANCEL   = 2


dim sUnc ' As String
dim sUnr ' As String
sUnc = vbcrlf & vbcrlf & "Your system remains unchanged."
sUnr = "Unrecoverable error"

Dim ibtn
Dim wshShell
Set wshShell = Wscript.CreateObject("Wscript.shell")

dim bOK
bOK = true   

If bOK Then
    Err.Clear()
    Set objWMIService = GetObject("winmgmts:\root\cimv2")
    bOK = (Err.Number = 0)
End if

if bOK Then
    Err.Clear()
    strQuery = "SELECT * FROM Win32" & "_" & "OperatingSystem"
    Set colOS = objWMIService.ExecQuery(strQuery)
    bOK = (Err.Number = 0)
End If

gotxp = False
mfgAgilent = False
If bOK Then
    For Each objOS In colOS
        For Each propOS In objOS.Properties_
            Select Case propOS.Name
                Case "Caption"
                    If InStr(propOS.Value, " XP ") Then gotxp = True
                Case "Version"
                    If propOS.Value = "5.1.2600" Then gotxp = True
                Case "BuildNumber"
                    If propOS.Value = 2600 Then gotxp = True
                Case "Manufacturer"
                    If InStr(propOS.Value, "Agilent") Then mfgAgilent = True
                Case Else
            End Select
        Next
    Next
End If

If not bOK Then
    ibtn = wshShell.Popup("Unrecoverable WMI error while checking for Operating System." & sUnc,,sUnr,BTNOK+ICONBANG)
    Wscript.Quit(1)
End If

'ibtn = wshShell.Popup("This script was made for your operating system",,"",BTNOK)

Dim objWMIService 'As WbemScripting.SWbemServicesEx
Dim colQF 'As WbemScripting.SWbemObjectSet
Dim objQF 'As WbemScripting.SWbemObjectEx
Dim strQuery 'As String

if bOK Then
    Err.Clear()
    Set objWMIService = GetObject("winmgmts:\root\cimv2")
    bOK = (Err.Number = 0)
End If

if bOK Then
    Err.Clear()
    strQuery = "SELECT * FROM Win32_QuickFixEngineering"
    Set colQF = objWMIService.ExecQuery(strQuery)
    bOK = (Err.Number = 0)
End If

bGothotfix = False
If bOK Then
    For Each objQF In colQF
        If InStr(objQF.HotFixID, "Q967715") Then bGothotfix = True
        If InStr(objQF.HotFixId, "KB967715") Then bGothotfix = True
    Next
End If

If not bOK Then
    ibtn = wshShell.Popup("Unrecoverable WMI error while checking for Hotfix." & sUnc,,sUnr,BTNOK+ICONBANG)
    Wscript.Quit(1)
End If



'If bGothotfix Then
'    MsgBox("KB967715 is installed")
'Else
'    MsgBox("KB967715 may not be installed")
'End If

set objWMIService = Nothing
Set colQF = Nothing
Err.Clear()

Const HKEY_CURRENT_USER = &H80000001
Const HKEY_LOCAL_MACHINE = &H80000002
Const REG_DWORD = 4
Const KEY_QUERY_VALUE = 1
Const KEY_SET_VALUE = 2
Const KEY_QCDS_VALUE = 3 

Dim HKEY 'As Integer
HKEY = HKEY_LOCAL_MACHINE

If bOK Then
    Err.Clear()
    strComputer = "."
    Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    bOK = (Err.Number = 0)
End If

If not bOK Then
    ibtn = wshShell.Popup("Unrecoverable WMI error while obtaining registry access." & sUnc,,sUnr,BTNOK+ICONBANG)
    Wscript.Quit(3)
End If

bAutoRunDisabled = False
If bOK Then
    strKeyPath = "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    strValueName = "NoDriveTypeAutoRun"

    rc = oReg.GetDWORDValue(HKEY, strKeyPath, strValueName, dwValue)
    If rc <> 0 and rc <> 1 and rc <> 2 Then
        ibtn = wshShell.Popup("Unrecoverable error " & CStr(rc) & " from GetDWORDValue function." & sUnc,,sUnr,BTNOK+ICONBANG)
        Wscript.Quit(6)
        bOK = false    ' Should not drop through
    End If
    If rc = 0 Then
        If ((dwValue And &H000000B5) = &H000000B5) Then bAutoRunDisabled = True
    Else
        ' ibtn = wshShell.Popup("Recoverable error " & CStr(rc) & " from GetDWORDValue function.",,"",BTNOK+ICONBANG)
    End If
End If

HKEY = HKEY_LOCAL_MACHINE
Dim strValue 'As String

If bGothotfix Then
    bCERTAutorunDisabled = True    ' If hotfix installed, we don't need the CERT fix
Else
    bCERTAutorunDisabled = False    ' If no hotfix, then we need to check for CERT patch
End If

If bOK and not bCERTAutoRunDisabled Then
    strKeyPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\IniFileMapping\Autorun.inf"
    strValueName = ""

    rc = oReg.GetStringValue(HKEY, strKeyPath, strValueName, strValue)
    If rc <> 0 and rc <> 1 and rc <> 2 Then
        ibtn = wshShell.Popup("Unrecoverable error " & CStr(rc) & " from GetStringValue function." & sUnc,,sUnr,BTNOK+ICONBANG)
        Wscript.Quit(6)
        bOK = false    ' Should not drop through
    End If
    If rc = 0 Then
        If strValue = "@SYS:DoesNotExist" Then bCERTAutorunDisabled = True
    Else
        ' ibtn = wshShell.Popup("Recoverable error " & CStr(rc) & " from GetStringValue function.",,"",BTNOK+ICONBANG)
    End If
End If

If bAutorunDisabled and bCERTAutorunDisabled Then 
    sMsg = "  " 
    sVS = "Vulnerability Status"
    sMsg =  sMsg & " "  & vbcrlff & vbcrlf
    sMsg =  sMsg & "PC Protected"  & vbcrlff & vbcrlf
    sMsg =  sMsg & " "  & vbcrlff & vbcrlf
    sMsg =  sMsg & "Autorun Disabled"  & vbcrlff & vbcrlf
    sMsg =  sMsg & " "  & vbcrlff & vbcrlf 
    sMsg =  sMSG & "No necesita ninguna accion"  + vbCrLf + "No need to take any action"  & vbcrlf 
    ibtn = wshShell.Popup(sMsg,,sVS,BTNOK+ICONINFO)
    Wscript.Quit(0)
End If 

Dim sMsg 'As String
sMsg = " " & vbcrlf 
sVS = "Vulnerability Status"

If bAutorunDisabled Then
    sMsg = sMsg &  "Autorun Active" & vbcrlf & vbcrlf
Else
    sMsg = sMsg &  "Autorun Active" & vbcrlf & vbcrlf
End If

If bGothotfix Then
    sMsg = sMsg &  "PC Vulnerable " & vbcrlf & vbcrlf
Else
    sMsg = sMsg &  "PC Vulnerable" & vbcrlf & vbcrlf
End If

If bAutorunDisabled and not bCERTAutorunDisabled Then
    sMsg = sMSG & "Desea desactivar autorun? (recomendado)"  + vbCrLf + "Do you want to disable autorun? (recommended)"

    ibtn = wshShell.Popup(sMsg,,sVS,BTNOKCANCEL+ICONBANG)
    If ibtn <> IBTNOK Then
        ibtn = wshShell.PopUp("Operación Cancelada - Operation Cancelled",,sVS,BTNOK+ICONSTOP)

        Wscript.Quit(0)
    End If
End If

If not bAutorunDisabled and bCERTAutorunDisabled Then
    sMsg = sMSG & "Desea desactivar autorun? (recomendado)"  + vbCrLf + "Do you want to disable autorun? (recommended)"
    ibtn = wshShell.Popup(sMsg,,sVS,BTNOKCANCEL+ICONBANG)
    If ibtn <> IBTNOK Then
        ibtn = wshShell.PopUp("Operación cancelada - Operation Cancelled",,sVS,BTNOK+ICONSTOP)
        Wscript.Quit(0)
    End If
End If

If not bAutorunDisabled and not bCERTAutorunDisabled Then
    sMsg = sMSG & "Desea desactivar autorun? (recomendado)"  + vbCrLf + "Do you want to disable autorun? (recommended)"

    ibtn = wshShell.Popup(sMsg,,sVS,BTNOKCANCEL+ICONBANG)
    If ibtn <> IBTNOK Then
        ibtn = wshShell.PopUp("Operación cancelada - Operation Cancelled",,sVS,BTNOK+ICONSTOP)
        Wscript.Quit(0)
    End If
End If

If not bAutoRunDisabled Then
    strKeyPath = "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    strValueName = "NoDriveTypeAutoRun"

    dwValue = &H000000FF
    rc = WshShell.RegWrite("HKLM\" & strKeyPath & "\" & strValueName, dwValue, "REG_DWORD")
    If rc <> 0 Then
        ibtn = wshShell.Popup("Unrecoverable error " & Cstr(rc) & " from RegWrite(REG_DWORD) function" & sUnc,,sUnr,BTNOK+ICONBANG)
        Wscript.Quit(8)
    End If
End If

If not bCERTAutorunDisabled Then
    strKeyPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\IniFileMapping\Autorun.inf"
    strValueName = ""

    strValue = "@SYS:DoesNotExist"
    rc = WshShell.RegWrite("HKLM\" & strKeyPath & "\" & strValueName, strValue, "REG_SZ")
    If rc <> 0 Then
        ibtn = wshShell.Popup("Unrecoverable error " & Cstr(rc) & " from RegWrite (REG_SZ) function",,sUnr,BTNOK+ICONBANG)
        Wscript.Quit(8)
    End If
End If


    ibtn = wshShell.Popup("Autorun Desactivado. Los cambios tendran efecto al reiniciar el PC"  + vbCrLf + "Autorun Disabled. The changes will take effect when you restart PC",,sVS,BTNOK+ICONINFO)
    Wscript.Quit(0)

On Error GoTo 0