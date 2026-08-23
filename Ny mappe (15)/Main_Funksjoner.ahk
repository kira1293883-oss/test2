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
LagreNyeHurtigtaster(g, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11) {
    global HK_Pause, HK_Extract, HK_Gui, HK_Speed, HK_Lock, HK_Round, HK_SaveNote, HK_Link, HK_Feed, HK_Notepad, HK_Folder
    gamleKnapper := [HK_Pause, HK_Extract, HK_Gui, HK_Speed, HK_Lock, HK_Round, HK_SaveNote, HK_Link, HK_Feed, HK_Notepad, HK_Folder]
    for k in gamleKnapper {
        try Hotkey(k, "Off")
    }

    nyeVerdier := Map(
        "Pause-knapp", p1, "Utpakk-knapp", p2, "Passordregister", p3, "Farts-knapp", p4,
        "Lås passord", p5, "Kopier runde", p6, "Lagre i Notepad", p7, "Lagre lenke (URL)", p8,
        "Mate passord", p9, "Åpne Notepad-logg", p10, "Endre Mappe", p11)
    kallbaker := Map(
        "Pause-knapp", (*)=>CallPause(), "Utpakk-knapp", (*)=>TriggerUtpakkingLive(),
        "Passordregister", (*)=>TriggerF11Register(), "Farts-knapp", (*)=>TriggerF7Fartspanel(),
        "Lås passord", (*)=>VekslLåstPassordF11(), "Kopier runde", (*)=>KopierRundePassordF11(),
        "Lagre i Notepad", (*)=>LagrePassordINotepadF11(), "Lagre lenke (URL)", (*)=>LagreLenkeF11(),
        "Mate passord", (*)=>MaterPassordF11(), "Åpne Notepad-logg", (*)=>ÅpnePassordNotatF11(),
        "Endre Mappe", (*)=>F5_EndreMappeLive())

    ; Registrer én og én slik at vi vet EKSAKT hvilken tast som feiler, i stedet
    ; for én stor try-blokk som bare sier "noe gikk galt" uten å si hva.
    feilet := ""
    for navn, verdi in nyeVerdier {
        try {
            Hotkey(verdi, kallbaker[navn])
        } catch as e {
            feilet .= navn " ('" verdi "'): " e.Message "`n"
        }
    }

    if (feilet != "") {
        MsgBox("⚠️ Følgende taster kunne IKKE registreres:`n`n" feilet "`nVanligste årsak: et annet program (f.eks. skjermopptaker, nettleser) bruker allerede denne tasten globalt, eller tasten er skrevet feil (bruk AHK-syntaks, f.eks. ^!f for Ctrl+Alt+F).", "Feil ved lagring av snarveier", 48)
        return
    }

    global HK_Pause := p1, HK_Extract := p2, HK_Gui := p3, HK_Speed := p4, HK_Lock := p5, HK_Round := p6, HK_SaveNote := p7, HK_Link := p8, HK_Feed := p9, HK_Notepad := p10, HK_Folder := p11
    g.Destroy()
    SoundPlay("*64")
    ToolTip("Oppdatert!")
    SetTimer(() => ToolTip(), -2000)
}

CallPause() {
    global ErPau
    ErPau := !ErPau
    SoundPlay(ErPau ? "*48" : "*64")
    ToolTip(ErPau ? "⏸️ SYSTEMET ER PAUSET" : "▶️ Systemet fortsetter...")
    SetTimer(() => ToolTip(), -1500)
}
