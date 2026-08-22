#Requires AutoHotkey v2.0
#SingleInstance Force

SetWinDelay(-1)
SetControlDelay(-1)
SetKeyDelay(-1, -1)

; ==============================================================================
; 1. GLOBALE VARIABLER (Minneallokering på toppnivå for å fjerne #Warn)
; ==============================================================================
global LogF := A_Desktop "\Vellykkede_Passord.txt"
global ErPau := false

; ⚡ ZERO DELAY: Satt direkte til 11 for å oppnå 0ms øyeblikkelig oppstart.
global SpdIdx := 11
global TypDelay := 0
global PostFilPause := 300
global WinRARPrioritet := "Normal"
global LydVarslingPå := true
global StlIdx := 1
global fartsGui := ""
global txtL1 := ""
global txtL2 := ""
global cfg := ""

global HK_Pause := "F2"
global HK_Extract := "F3"
global HK_Gui := "F11"
global HK_Speed := "F7"
global HK_Lock := "^!l"
global HK_Round := "^!r"
global HK_SaveNote := "^!s"
global HK_Link := "^!u"
global AutoClose_F1 := true
global AutoClose_F7 := true

global cbF1 := ""
global cbF7 := ""
global sysGui := ""
global SessionFile := "Lagrede_Koder.txt"
global SyncTurboModus := true
global UtpakkingsModus := "A"

; Forbeholder objektreferanser for/mot JA/NEI kontroller på F5
global btnResetFile := "", btnResetFileYes := "", btnResetFileNo := ""

; ==============================================================================
; 2. MODUL-INKLUDERING (Lastes inn først for å registrere alle funksjoner)
; ==============================================================================
#Include .\Main_Konfigurasjon.ahk
#Include .\Main_Funksjoner.ahk
#Include .\Main_Vinduer.ahk
#Include .\Main_PassordLogikk.ahk
#Include .\Main_F11Register.ahk
#Include .\Part_UtpakkingsMotor.ahk

; ==============================================================================
; 3. INTEGRERTE BRYTERFUNKSJONER FOR F5 
; ==============================================================================
F5_ToggleAC_F1(btn, *) {
    global AutoClose_F1
    AutoClose_F1 := !AutoClose_F1
    SoundPlay(AutoClose_F1 ? "*64" : "*48")
    btn.Opt(AutoClose_F1 ? "+Background155724 cWhite" : "+Background721C24 cWhite")
    btn.Text := "F1 Panel: " (AutoClose_F1 ? "PÅ" : "AV")
}

F5_ToggleAC_F7(btn, *) {
    global AutoClose_F7
    AutoClose_F7 := !AutoClose_F7
    SoundPlay(AutoClose_F7 ? "*64" : "*48")
    btn.Opt(AutoClose_F7 ? "+Background155724 cWhite" : "+Background721C24 cWhite")
    btn.Text := "F7 Fart: " (AutoClose_F7 ? "PÅ" : "AV")
}

F5_EndreMappeLive(*) {
    global SrcM, sysGui
    try {
        if (nyMappe := DirSelect("*" SrcM, 3, "Velg ny arbeidskilde:")) {
            SrcM := RegExReplace(nyMappe, "\\$")
            kortSti := (StrLen(SrcM) > 42) ? SubStr(SrcM, 1, 40) "..." : SrcM
            sysGui["StiViser"].Value := kortSti
            SoundPlay("*64")
        }
    }
}

F5_ÅpneLoggLive(*) {
    global LogF
    try {
        if FileExist(LogF) {
            Run(LogF)
        } else {
            MsgBox("Ingen loggfil opprettet enda på skrivebordet.", "System", 64)
        }
    }
}

F5_VisSlettFilValg(*) {
    global btnResetFile, btnResetFileYes, btnResetFileNo
    try {
        btnResetFile.Opt("+Hidden")
        btnResetFileYes.Opt("-Hidden")
        btnResetFileNo.Opt("-Hidden")
        SoundPlay("*64")
    }
}

F5_SkjulSlettFilValg(*) {
    global btnResetFile, btnResetFileYes, btnResetFileNo
    try {
        btnResetFileYes.Opt("+Hidden")
        btnResetFileNo.Opt("+Hidden")
        btnResetFile.Opt("-Hidden")
        SoundPlay("*48")
    }
}

F5_SlettFilBekreft(*) {
    global SessionFile, CyclusKart
    try {
        if FileExist(SessionFile)
            FileDelete(SessionFile)
        CyclusKart := []
        if (HasFunc("OppdatertCyclusPanelLiveF11"))
            OppdatertCyclusPanelLiveF11()
        SoundPlay("*16")
        ToolTip("Fil slettet og F11-køen nullstilt!")
        SetTimer(() => ToolTip(), -2000)
        F5_SkjulSlettFilValg()
    }
}

HåndterLukkF5Kontroll(*) {
    global sysGui
    try {
        if IsObject(sysGui) {
            sysGui.Destroy()
            sysGui := ""
        }
    }
}

HåndterVinduKlikkF5(wParam, lParam, msg, hwnd) {
    global sysGui
    try {
        if (IsObject(sysGui) and hwnd = sysGui.Hwnd) {
            PostMessage(0x00A1, 2, 0, , "ahk_id " sysGui.Hwnd)
        }
    }
}

; ==============================================================================
; 4. AUTOMATISERTE SYSTEMHENDELSER & TIMER-TRÅDER
; ==============================================================================
SetTimer(SjekkKlikkUtenfor, 200)

; Registrerer de krasjsikre funksjonstastene i Windows-registeret
Hotkey(HK_Pause, (*)=>CallPause())
Hotkey(HK_Extract, (*)=>TriggerUtpakkingLive())
Hotkey(HK_Gui, (*)=>TriggerF11Register())
Hotkey(HK_Speed, (*)=>TriggerF7Fartspanel())
Hotkey(HK_Lock, (*)=>VekslLåstPassordF11())
Hotkey(HK_Round, (*)=>KopierRundePassordF11())
Hotkey(HK_SaveNote, (*)=>LagrePassordINotepadF11())
Hotkey(HK_Link, (*)=>LagreLenkeF11())

; Velkomstmelding ved oppstart
try {
    MsgBox("🤖 MODULÆRT DELUXE SYSTEM STARTET!`n`n🚀 TURBO 0MS AKTIVERT SOM STANDARD!`n`nF1: Knapper | F3: Pakk ut | F5: Auto-Close | F7: Fart | F10: Tema | F11: Passordregister", "System", 64)
}

; Standard direktetast for knappekonfigurering
F1::TriggerF1Knappeoppsett()

; ==============================================================================
; 5. AVANSERT SYSTEMKONTROLLPANEL (F5) - UTVIDET & LIVE CONFIG
; ==============================================================================
F5:: {
    global sysGui, AutoClose_F1, AutoClose_F7, cbF1, cbF7, SrcM, LogF, SessionFile
    global btnResetFile, btnResetFileYes, btnResetFileNo
    try {
        if IsObject(sysGui) and WinExist("ahk_id " sysGui.Hwnd) {
            sysGui.Destroy()
            sysGui := ""
            return
        }
        
        sysGui := Gui("-Caption -Border +AlwaysOnTop +0x02000000")
        sysGui.BackColor := "1A1A1A"
        sysGui.MarginX := 25, sysGui.MarginY := 25
        
        ; Overskrift og Status
        sysGui.SetFont("s11 cWhite Bold", "Segoe UI")
        sysGui.Add("Text", "w320 h25 +0x200", "🔱 AVANSERT SYSTEMKONTROLL:")
        
        ; MAPPEKONTROLL LIVE
        sysGui.SetFont("s9 cWhite Bold")
        sysGui.Add("Text", "w320 xm y+5", "📁 AKTIV KILDEMAPPE:")
        sysGui.SetFont("s8.5 cAAAAAA Normal")
        kortSti := (StrLen(SrcM) > 42) ? SubStr(SrcM, 1, 40) "..." : SrcM
        sysGui.Add("Text", "w320 xm y+3 vStiViser", kortSti)
        
        sysGui.SetFont("s9 cWhite Bold")
        sysGui.Add("Button", "w155 h30 xm y+8 -Theme +Background3A3A3A", "📁 Endre Mappe").OnEvent("Click", F5_EndreMappeLive)
        sysGui.Add("Button", "w155 h30 x+10 -Theme +Background3A3A3A", "📝 Åpne Passordlogg").OnEvent("Click", F5_ÅpneLoggLive)
        
        sysGui.SetFont("s8 c888888 Normal")
        sysGui.Add("Text", "w320 xm y+5", "------------------------------------------------------------------")
        
        ; AUTO-CLOSE SEKSJON (Live status brytere)
        sysGui.SetFont("s9 cWhite Bold")
        sysGui.Add("Text", "w320 xm y+5", "🔒 AUTOMATISK LUKKING (AUTO-CLOSE):")
        
        sysGui.SetFont("s8.5")
        cbF1 := sysGui.Add("Button", "w155 h30 xm y+8 -Theme " (AutoClose_F1 ? "+Background155724 cWhite" : "+Background721C24 cWhite"), "F1 Panel: " (AutoClose_F1 ? "PÅ" : "AV"))
        cbF1.OnEvent("Click", F5_ToggleAC_F1)
        
        cbF7 := sysGui.Add("Button", "w155 h30 x+10 yp -Theme " (AutoClose_F7 ? "+Background155724 cWhite" : "+Background721C24 cWhite"), "F7 Fart: " (AutoClose_F7 ? "PÅ" : "AV"))
        cbF7.OnEvent("Click", F5_ToggleAC_F7)
        
        sysGui.SetFont("s8 c888888 Normal")
        sysGui.Add("Text", "w320 xm y+5", "------------------------------------------------------------------")
        
        ; ØKT-RENSING MED TRYGG JA/NEI BEKREFTELSE
        sysGui.SetFont("s9 cWhite Bold")
        sysGui.Add("Text", "w320 xm y+5", "♻️ SIKKERHET & RECOVERY:")
        
        btnResetFile := sysGui.Add("Button", "w320 h32 xm y+8 -Theme +Background333333 cRed", "🗑️ Slett Lagrede Koder (.txt)")
        btnResetFile.OnEvent("Click", F5_VisSlettFilValg)
        
        btnResetFileYes := sysGui.Add("Button", "w155 h32 xm y+8 -Theme +Background155724 cWhite +Hidden", "✔️ JA, SLETT FIL")
        btnResetFileYes.OnEvent("Click", F5_SlettFilBekreft)
        
        btnResetFileNo := sysGui.Add("Button", "w155 h32 x+10 yp -Theme +Background444444 cWhite +Hidden", "❌ NEI, AVBRYT")
        btnResetFileNo.OnEvent("Click", F5_SkjulSlettFilValg)
        
        ; Bunnkontroller
        sysGui.SetFont("s9 cWhite Bold")
        ; 🔒 KORRIGERT: Endret fra 'H鍵terLukkF5Kontroll' til det korrekte 'HåndterLukkF5Kontroll'
        sysGui.Add("Button", "w320 h35 xm y+20 -Theme +Background222222", "✖ Lukk Kontrollpanel").OnEvent("Click", HåndterLukkF5Kontroll)
        
        OnMessage(0x0201, HåndterVinduKlikkF5)
        sysGui.Show("W370")
    }
}

; ==============================================================================
; 6. SYSTEM-NØDBREMS (F8) 
; ==============================================================================
F8:: {
    try {
        SoundPlay("*16")
        while ProcessExist("WinRAR.exe") {
            ProcessClose("WinRAR.exe")
        }
        while ProcessExist("7zG.exe") {
            ProcessClose("7zG.exe")
        }
            
        ToolTip("🚨 NØDBREMS FULLFØRT: Bakgrunnsprosesser kvalt!")
        SetTimer(() => ToolTip(), -2500)
    }
}            
