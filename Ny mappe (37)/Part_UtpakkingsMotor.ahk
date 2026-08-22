#Requires AutoHotkey v2.0

; Forward-deklarasjoner for å tilfredsstille #Warn i delte moduler
global CyclusKart, ErPau, SpdIdx, TypDelay, SrcM, SucM, FailM, LogF, fartsGui, txtL1, txtL2, Themes, StlIdx, SisteFeiledeFiler

; ==============================================================================
; SEKSJON 1: DET SENTRALE UTPAKKINGSANLEGGET (F3)
; Bruker KUN passordet som er tilordnet hver fil i F11-registeret.
; Ingen gjetting/brute-force lenger — én fil, ett passord, ett forsøk.
; ==============================================================================
TriggerUtpakkingLive() {
    global CyclusKart, ErPau, SpdIdx, TypDelay, SrcM, SucM, FailM, LogF, PostFilPause, WinRARPrioritet, LydVarslingPå, RundeTeller, SisteFeiledeFiler

    RundeTeller++
    denneRunden := RundeTeller

    ; Plukk ut kun rader som faktisk har fått et passord tilordnet
    koe := []
    for idx, element in CyclusKart {
        if (element.p != "VENTER_PÅ_MATING" and element.p != "" and !(element.HasOwnProp("lastNed") and element.lastNed))
            koe.Push(element)
    }

    if (koe.Length = 0) {
        return MsgBox("Ingen filer i F11-registeret har fått passord ennå. Åpne F11 og mat inn passord først.", "System")
    }

    ; ⚡ ZERO DELAY FORMEL: Når SpdIdx tvinges til 11 blir resultatet nøyaktig 0ms delay!
    delay := (11 - SpdIdx) * 200
    dash := Gui("+AlwaysOnTop -MinimizeBox -Caption +Border"), dash.BackColor := "1A1A1A"
    dash.SetFont("s11 cWhite Bold", "Segoe UI"), dash.Add("Text", "w420 vFT", "Forbereder...")
    dash.SetFont("s9 cAAAAAA w400"), dash.Add("Text", "w420 y+5 vPT", "Venter...")
    dash.SetFont("s10 cWhite Bold"), bar := dash.Add("Progress", "w420 h15 y+10 cGreen Background333333 Smooth", 0)
    dash.Show("X" (A_ScreenWidth//2 - 220) " Y20 W440")
    tot := koe.Length
    exe := A_ProgramFiles "\WinRAR\WinRAR.exe"

    ferdigeFiler := []

    try {
        for idx, element in koe {
            while (ErPau)
                Sleep(500)

            nam := element.f
            p   := element.p

            fullSti := ""
            Loop Files, SrcM "\" nam ".*" {
                fullSti := A_LoopFilePath
                break
            }
            if (fullSti == "")
                continue

            dash["FT"].Value := "📁 [" idx "/" tot "] " nam
            dash["PT"].Value := "🔑 Bruker tilordnet passord..."
            bar.Value := Integer((idx/tot)*100)

            outD := SrcM "\" nam
            if !DirExist(outD)
                DirCreate(outD)

            if (delay > 0)
                Sleep(delay + 100)
            else
                Sleep(10)

            ok := false
            try {
                Run('"' exe '" x -p"' p '" -y -ibck "' fullSti '" "' outD '"', , "Hide", &winPID)
                if (winPID) {
                    ProcessSetPriority(WinRARPrioritet, winPID)
                    status := ProcessWaitClose(winPID)
                } else {
                    status := -1
                }
            } catch {
                status := -1
            }

            if (status = 0) {
                hasF := false
                Loop Files, outD "\*.*", "R" {
                    hasF := true
                    break
                }
                ok := hasF
            }
            if (!ok)
                try DirDelete(outD, 1)

            try {
                if (ok) {
                    FileAppend("FIL: " nam " -> OK med tilordnet passord`n", LogF, "UTF-8")
                    LagreAutoPassordF11(nam, p, denneRunden)
                    if (LydVarslingPå)
                        TrayTip("Saved!", nam, 1)
                } else {
                    FileAppend("FIL: " nam " -> FEILET (feil passord eller korrupt arkiv)`n", LogF, "UTF-8")
                    if (LydVarslingPå)
                        TrayTip("Failed!", nam, 3)
                }
            }

            ferdigeFiler.Push({f: nam, arkivSti: fullSti, utpakketMappe: outD, ok: ok})
            Sleep(PostFilPause)
        }

        ; --- Merk resultater med snarveier (samme enkle metode som originalen) ---
        for idx, res in ferdigeFiler {
            målMappe := res.ok ? SucM : FailM
            if !DirExist(målMappe)
                DirCreate(målMappe)

            try FileCreateShortcut(res.arkivSti, målMappe "\" res.f ".lnk")

            ; Utpakket mappe ligger fortsatt i SrcM — behold den ved suksess,
            ; slett den ved feil (samme oppførsel som originalen).
            if (!res.ok)
                try DirDelete(res.utpakketMappe, 1)
        }

        ; Fjern KUN de vellykkede filene fra F11-køen. Mislykkede filer blir
        ; liggende i køen (klare for nytt passord) slik at de kan prøves på nytt.
        vellykkedeNavn := Map()
        feiledeNavn := []
        for idx, res in ferdigeFiler {
            if (res.ok)
                vellykkedeNavn[res.f] := true
            else
                feiledeNavn.Push(res.f)
        }
        nyKø := []
        for idx, element in CyclusKart {
            if (vellykkedeNavn.Has(element.f))
                continue
            for idx2, fn in feiledeNavn {
                if (element.f == fn) {
                    element.p := "VENTER_PÅ_MATING"   ; klar for nytt/korrigert passord
                    break
                }
            }
            nyKø.Push(element)
        }
        CyclusKart := nyKø
        SisteFeiledeFiler := feiledeNavn
        if (HasFunc("OppdatertCyclusPanelLiveF11"))
            OppdatertCyclusPanelLiveF11()

        dash.Destroy()
        if (LydVarslingPå)
            SoundPlay("*64")
        meldingTekst := "FULLFØRT (Runde " denneRunden ")! " ferdigeFiler.Length " fil(er) behandlet."
        if (feiledeNavn.Length > 0) {
            feiletekst := ""
            for idx, fn in feiledeNavn
                feiletekst .= "`n• " fn
            meldingTekst .= "`n`n⚠️ " feiledeNavn.Length " fil(er) FEILET og ligger fortsatt i F11-køen, klare for nytt passord:" feiletekst "`n`nÅpne F11 og bruk '🔁 Prøv mislykkede filer på nytt' etter å ha rettet passordet."
        } else
            meldingTekst .= "`n`nPassordene er auto-lagret i Notepad-loggen — bruk 'Kopier passord fra runde' i F11 for å hente dem ut samlet."
        MsgBox(meldingTekst, "Ferdig")
    } catch {
        if IsObject(dash)
            dash.Destroy()
        MsgBox("⚠️ En uventet feil oppstod under utpakkingen, men systemet ruller videre.", "Systemfeil")
    }
}

; ==============================================================================
; SEKSJON 2: HASTIGHETSKONTROLL PANEL (F7) — uendret, samme reaksjon som før.
; Delayen brukes nå per fil i F11-køen istedenfor per passord-gjett.
; ==============================================================================
TriggerF7Fartspanel() {
    global SpdIdx, TypDelay, PostFilPause, WinRARPrioritet, LydVarslingPå, fartsGui, txtL1, txtL2, txtL3
    try {
        if IsObject(fartsGui) and WinExist("ahk_id " fartsGui.Hwnd) {
            fartsGui.Destroy()
            fartsGui := ""
            return
        }
    }
    try {
        SoundPlay("*64")
        fartsGui := Gui("-Caption -Border +AlwaysOnTop"), fartsGui.BackColor := "1A1A1A"
        OnMessage(0x0201, WM_LBUTTONDOWN_FARTSGUI_COMPACT)
        fartsGui.MarginX := 20, fartsGui.MarginY := 20, fartsGui.SetFont("s10 cWhite Bold", "Segoe UI")
        fartsGui.Add("Text", "w320", "⚡ HURTIGVALG:")
        fartsGui.SetFont("s8.5 cWhite Bold")
        fartsGui.Add("Button", "w98 h28 xm y+8 -Theme +Background155724", "🚀 Turbo").OnEvent("Click", (*) => BrukFartsPresetF7("Turbo"))
        fartsGui.Add("Button", "w98 h28 x+8 yp -Theme +Background8A6D00", "⚖️ Balansert").OnEvent("Click", (*) => BrukFartsPresetF7("Balansert"))
        fartsGui.Add("Button", "w98 h28 x+8 yp -Theme +Background721C24", "🐢 Skånsom").OnEvent("Click", (*) => BrukFartsPresetF7("Skånsom"))

        fartsGui.SetFont("s10 cWhite Bold")
        fartsGui.Add("Text", "w320 xm y+18", "Slider 1: Disk-forsinkelse (1 - 11):")
        minSlider1 := fartsGui.Add("Slider", "w300 Range1-11 ToolTip +Background1A1A1A", SpdIdx)
        minSlider1.OnEvent("Change", HåndterDiskMotorKompakt)
        fartsGui.SetFont("s9 cAAAAAA w400")
        txtL1 := fartsGui.Add("Text", "w300 xm", "Diskfart: " SpdIdx (SpdIdx = 11 ? " (0ms Turbo)" : ""))

        fartsGui.SetFont("s10 cWhite Bold")
        fartsGui.Add("Text", "w320 xm y+12", "Slider 2: Taste-delay (0 - 250ms):")
        minSlider2 := fartsGui.Add("Slider", "w300 Range0-250 ToolTip +Background1A1A1A", TypDelay)
        minSlider2.OnEvent("Change", HåndterTasteMotorKompakt)
        fartsGui.SetFont("s9 cAAAAAA w400")
        txtL2 := fartsGui.Add("Text", "w300 xm", "Taste-delay: " TypDelay " ms")

        fartsGui.SetFont("s10 cWhite Bold")
        fartsGui.Add("Text", "w320 xm y+12", "Slider 3: Pause mellom filer (0 - 2000ms):")
        minSlider3 := fartsGui.Add("Slider", "w300 Range0-2000 ToolTip +Background1A1A1A", PostFilPause)
        minSlider3.OnEvent("Change", HåndterPauseMotorKompakt)
        fartsGui.SetFont("s9 cAAAAAA w400")
        txtL3 := fartsGui.Add("Text", "w300 xm", "Filpause: " PostFilPause " ms")

        fartsGui.SetFont("s10 cWhite Bold")
        fartsGui.Add("Text", "w320 xm y+12", "WinRAR-prioritet:")
        ddPrio := fartsGui.Add("DropDownList", "w300 xm Choose" PrioritetIndeksF7(WinRARPrioritet), ["Low", "BelowNormal", "Normal", "AboveNormal", "High"])
        ddPrio.OnEvent("Change", HåndterPrioritetKompakt)

        fartsGui.SetFont("s9 cWhite Normal")
        cbLyd := fartsGui.Add("Checkbox", "w300 xm y+15 cWhite", "🔊 Lydvarsler ved ferdig/feilet fil")
        cbLyd.Value := LydVarslingPå
        cbLyd.OnEvent("Click", HåndterLydKompakt)

        fartsGui.SetFont("s10 cWhite Bold")
        fartsGui.Add("Button", "w320 xm y+20 +Background333333", "✖ Lukk Fartspanel").OnEvent("Click", HukkLukkFartsKallback)
        fartsGui.Show()
    }
}

; ==============================================================================
; HURTIGVALG-PRESETS — setter alle tre slidere med ett klikk
; ==============================================================================
BrukFartsPresetF7(navn) {
    global SpdIdx, TypDelay, PostFilPause, fartsGui
    if (navn = "Turbo")
        SpdIdx := 11, TypDelay := 0, PostFilPause := 100
    else if (navn = "Balansert")
        SpdIdx := 8, TypDelay := 20, PostFilPause := 300
    else if (navn = "Skånsom")
        SpdIdx := 3, TypDelay := 80, PostFilPause := 800

    ; Enkleste robuste måte å oppdatere alle kontroller på: bygg panelet på nytt
    try {
        if IsObject(fartsGui)
            fartsGui.Destroy()
        fartsGui := ""
    }
    SoundPlay("*64")
    TriggerF7Fartspanel()
    ToolTip("⚡ Preset aktivert: " navn)
    SetTimer(() => ToolTip(), -1500)
}

PrioritetIndeksF7(navn) {
    liste := ["Low", "BelowNormal", "Normal", "AboveNormal", "High"]
    for idx, v in liste
        if (v = navn)
            return idx
    return 3
}

HåndterDiskMotorKompakt(s, *) {
    try {
        global SpdIdx := s.Value
        txtL1.Value := "Diskfart: " s.Value (s.Value = 11 ? " (0ms Turbo)" : "")
    }
}

HåndterTasteMotorKompakt(s, *) {
    try {
        global TypDelay := s.Value
        txtL2.Value := "Taste-delay: " s.Value " ms"
    }
}

HåndterPauseMotorKompakt(s, *) {
    try {
        global PostFilPause := s.Value
        txtL3.Value := "Filpause: " s.Value " ms"
    }
}

HåndterPrioritetKompakt(dd, *) {
    try {
        global WinRARPrioritet := dd.Text
    }
}

HåndterLydKompakt(cb, *) {
    try {
        global LydVarslingPå := cb.Value
    }
}

HukkLukkFartsKallback(*) {
    try {
        if IsObject(fartsGui)
            fartsGui.Destroy()
        global fartsGui := ""
    }
}

WM_LBUTTONDOWN_FARTSGUI_COMPACT(wParam, lParam, msg, hwnd) {
    global fartsGui
    try {
        if (IsObject(fartsGui) and hwnd = fartsGui.Hwnd)
            PostMessage(0x00A1, 2, 0, , "ahk_id " fartsGui.Hwnd)
    }
}

; ==============================================================================
; SEKSJON 3: INTERNT TEMASYSTEM (F10) — styrer nå F11-registeret istedenfor F6
; ==============================================================================
F10:: {
    global Themes
    try {
        m := Menu()
        stilerIkoner := ["🌙 ", "⚡ ", "🌸 ", "📟 ", "💻 ", "⚙️ ", "🌋 ", "🔥 ", "🐳 ", "⚫ "]
        for idx, t in Themes
            m.Add(stilerIkoner[idx] . t.n, KlikketTemaKallbackKompakt)
        m.Add()
        m.Add("Avbryt", (*) => SoundPlay("*64")), m.Show()
    }
}

KlikketTemaKallbackKompakt(ItemName, ItemPos, MyMenu) {
    global StlIdx, Themes
    try {
        StlIdx := ItemPos
        try {
            SoundPlay(Themes[ItemPos].HasProp("s") ? Themes[ItemPos].s : Themes[ItemPos].sound)
        }
        if HasFunc("UpdStl11")
            UpdStl11(true)
        ToolTip("Stil aktivert: " Themes[ItemPos].n)
        SetTimer(() => ToolTip(), -2000)
    }
}

HasFunc(FuncName) {
    try return IsObject(Func(FuncName))
    return false
}
