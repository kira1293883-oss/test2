#Requires AutoHotkey v2.0

; ==============================================================================
; SEKSJON 1: AUTO-CLOSE FOR FLYKTIGE VINDUER (F1 og F7)
; ==============================================================================
SjekkKlikkUtenfor() {
    global fartsGui, cfg, AutoClose_F1, AutoClose_F7
    try {
        if (IsSet(AutoClose_F7) and AutoClose_F7 and IsObject(fartsGui) and WinExist("ahk_id " fartsGui.Hwnd) and !WinActive("ahk_id " fartsGui.Hwnd)) {
            fartsGui.Destroy()
            fartsGui := ""
        }
    }
    try {
        if (IsSet(AutoClose_F1) and AutoClose_F1 and IsObject(cfg) and HasProp(cfg, "Hwnd") and WinExist("ahk_id " cfg.Hwnd)) {
            if (!WinActive("ahk_id " cfg.Hwnd)) {
                cfg.Destroy()
                cfg := ""
            }
        }
    }
}

; ==============================================================================
; SEKSJON 2: PAUSE- OG HURTIGTASTKONTROLL
; ==============================================================================
LagreNyeHurtigtaster(g, p1, p2, p3, p4) {
    global HK_Pause, HK_Extract, HK_Gui, HK_Speed
    gamleKnapper := [HK_Pause, HK_Extract, HK_Gui, HK_Speed]
    for k in gamleKnapper {
        try Hotkey(k, "Off")
    }
    try {
        global HK_Pause := p1, HK_Extract := p2, HK_Gui := p3, HK_Speed := p4
        Hotkey(HK_Pause, (*)=>CallPause())
        Hotkey(HK_Extract, (*)=>TriggerUtpakkingLive())
        Hotkey(HK_Gui, (*)=>TriggerF11Register())
        Hotkey(HK_Speed, (*)=>TriggerF7Fartspanel())
        g.Destroy()
        SoundPlay("*64")
        ToolTip("Oppdatert!")
        SetTimer(() => ToolTip(), -2000)
    } catch {
        ToolTip("⚠️ FEIL TASTER!")
        SetTimer(() => ToolTip(), -2000)
    }
}

CallPause() {
    global ErPau
    ErPau := !ErPau
    SoundPlay(ErPau ? "*48" : "*64")
    ToolTip(ErPau ? "⏸️ SYSTEMET ER PAUSET" : "▶️ Systemet fortsetter...")
    SetTimer(() => ToolTip(), -1500)
}
