#Requires AutoHotkey v2.0

; ==============================================================================
; OMPROGRAMMERINGSTASTER PANEL (F1)
; ==============================================================================
TriggerF1Knappeoppsett() {
    global HK_Pause, HK_Extract, HK_Gui, HK_Speed, cfg
    try if IsObject(cfg) and WinExist("ahk_id " cfg.Hwnd)
        return LukkF1Oppsett()
    try {
        SoundPlay("*64")
        cfg := Gui("-Caption -Border +AlwaysOnTop +0x02000000")
        cfg.MarginX := 30, cfg.MarginY := 30, cfg.BackColor := "1A1A1A"
        cfg.SetFont("s10 cWhite Bold", "Segoe UI")
        cfg.Add("Text", "w270 h25 +0x200", "🔱 OMPROGRAMMERING TASTER:")
        cfg.SetFont("s9 cAAAAAA w400", "Segoe UI")
        cfg.Add("Text", "w120 xm y+15", "Pause-knapp:")
        iP := cfg.Add("Edit", "w140 x+10 r1 +Background333333 cWhite", HK_Pause)
        cfg.Add("Text", "w120 xm y+10", "Utpakk-knapp:")
        iE := cfg.Add("Edit", "w140 x+10 r1 +Background333333 cWhite", HK_Extract)
        cfg.Add("Text", "w120 xm y+10", "Passordregister:")
        iG := cfg.Add("Edit", "w140 x+10 r1 +Background333333 cWhite", HK_Gui)
        cfg.Add("Text", "w120 xm y+10", "Farts-knapp:")
        iFart := cfg.Add("Edit", "w140 x+10 r1 +Background333333 cWhite", HK_Speed)
        cfg.SetFont("s9 cWhite Bold")
        cfg.Add("Button", "w270 h32 xm y+20 -Theme +Background3A3A3A", "💾 Lagre Knapper").OnEvent("Click", (btn, *)=>LagreNyeHurtigtaster(cfg, iP.Value, iE.Value, iG.Value, iFart.Value))
        cfg.Add("Button", "w270 h32 xm y+10 -Theme +Background3A3A3A", "🔄 Reset Standard").OnEvent("Click", (btn, *)=>LagreNyeHurtigtaster(cfg, "F2", "F3", "F11", "F7"))
        cfg.Add("Button", "w270 h32 xm y+10 -Theme +Background222222", "✖ Lukk Oppsett").OnEvent("Click", LukkF1Oppsett)
        OnMessage(0x0201, HåndterVinduKlikkF1)
        cfg.Show("W330")
    }
}

LukkF1Oppsett(*) {
    global cfg
    try {
        if IsObject(cfg) {
            cfg.Destroy()
            cfg := ""
        }
    } catch {
        global cfg := ""
    }
}

HåndterVinduKlikkF1(wParam, lParam, msg, hwnd) {
    global cfg
    try {
        if (IsObject(cfg) and hwnd = cfg.Hwnd) {
            PostMessage(0x00A1, 2, 0, , "ahk_id " cfg.Hwnd)
        }
    }
}
