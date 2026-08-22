#Requires AutoHotkey v2.0

; ==============================================================================
; F11 CYCLUS REGISTER — erstatter det gamle F6-passordsenteret
; Én rad per fil i SrcM, med ETT spesifikt passord tilordnet hver fil.
; Ingen gjetting: F3 bruker kun det passordet som står ved siden av filen.
; ==============================================================================
global CyclusKart        := []     ; Array: {f: filnavn, p: passord/"VENTER_PÅ_MATING", lastNed: bool}
global CyclusTeller       := 0
global GjeldendeVenteFil  := ""
global cyclusGui          := "", lvCyclus := ""
global CyclusSkannIntervallms := 2000
global StørrelseSjekkKart := Map()
global PassordNotatFil    := A_Desktop "\Lagrede_Passord.txt"
global RundeTeller         := 0     ; Øker med 1 for hver F3-utpakkingsøkt ("Runde 1", "Runde 2" ...)
global RundeHarSkrevetHode := Map() ; Husker om vi har skrevet "=== RUNDE N ===" for denne runden ennå
global LåstPassordAktiv    := false ; Når true: nye filer som oppdages får automatisk LåstPassordVerdi
global LåstPassordVerdi    := ""
global lockBtnF11          := ""
global SisteFeiledeFiler   := []   ; Filnavn som feilet i siste F3-runde

SetTimer(UtførMappeSkanningF11, CyclusSkannIntervallms)

; Bygger " Owner<hwnd>" trygt — F11-panelet er ikke alltid åpent når disse
; funksjonene trigges via egendefinerte hurtigtaster (F1-oppsett).
EierAlternativF11() {
    global cyclusGui
    try
        if IsObject(cyclusGui) and WinExist("ahk_id " cyclusGui.Hwnd)
            return " Owner" cyclusGui.Hwnd
    return ""
}

; ==============================================================================
; F11 — ÅPNE/LUKK REGISTERPANEL
; ==============================================================================
TriggerF11Register() {
    global cyclusGui, lvCyclus, CyclusSkannIntervallms, Themes, StlIdx, lockBtnF11, LåstPassordAktiv, LåstPassordVerdi
    try {
        if IsObject(cyclusGui) and WinExist("ahk_id " cyclusGui.Hwnd) {
            cyclusGui.Destroy(), cyclusGui := ""
            return
        }
        st := Themes[StlIdx]
        cyclusGui := Gui("-Caption -Border +AlwaysOnTop")
        cyclusGui.BackColor := st.bg
        cyclusGui.MarginX := 25, cyclusGui.MarginY := 25
        cyclusGui.SetFont("s10 c" st.fg " Bold", "Segoe UI")
        cyclusGui.Add("Text", "x25 y25 w410 h25", "🔑 F11 PASSORDREGISTER [AKTIV KØ]:")

        cyclusGui.SetFont("s8.5 cD0D0D0 Normal", "Segoe UI")
        lvCyclus := cyclusGui.Add("ListView",
            "x25 y60 w410 h200 +VScroll +HScroll +0x2000000 Background" st.ft " c" st.fg " Grid",
            ["Filnavn i kø", "Passord"])

        cyclusGui.SetFont("s8.5 cWhite Bold")
        cyclusGui.Add("Button", "x25  y270 w130 h32 -Theme +Background3A3A3A", "🗑 Fjern valgt").OnEvent("Click", (*) => FjernValgtFraKøF11())
        cyclusGui.Add("Button", "x163 y270 w130 h32 -Theme +Background3A3A3A", "🧹 Tøm kø").OnEvent("Click", (*) => TømHeleKøenF11())
        cyclusGui.Add("Button", "x301 y270 w134 h32 -Theme +Background3A3A3A", "✏️ Sett passord").OnEvent("Click", (*) => SettPassordManueltF11())

        cyclusGui.Add("Button", "x25 y308 w410 h32 -Theme +Background3A3A3A", "💾 Lagre valgt i Notepad").OnEvent("Click", (*) => LagrePassordINotepadF11())

        cyclusGui.SetFont("s8.5 cWhite Bold")
        cyclusGui.Add("Button", "x25 y346 w410 h32 -Theme +Background3A3A3A", "🔗 Sett SAMME passord på valgte (Ctrl/Shift-klikk)").OnEvent("Click", (*) => SettPassordFlereF11())

        lockBtnF11 := cyclusGui.Add("Button", "x25 y384 w200 h32 -Theme +Background3A3A3A", LåstPassordAktiv ? "🔒 Låst: " LåstPassordVerdi : "🔓 Lås passord for nye filer")
        lockBtnF11.OnEvent("Click", (*) => VekslLåstPassordF11())
        cyclusGui.Add("Button", "x235 y384 w200 h32 -Theme +Background3A3A3A", "📋 Kopier passord fra runde").OnEvent("Click", (*) => KopierRundePassordF11())

        cyclusGui.Add("Button", "x25 y422 w410 h32 -Theme +Background3A3A3A", "📝 Åpne Notepad-loggen").OnEvent("Click", (*) => ÅpnePassordNotatF11())

        cyclusGui.Add("Button", "x25 y460 w410 h32 -Theme +Background3A3A3A", "🔁 Prøv mislykkede filer på nytt").OnEvent("Click", (*) => PrøvMislykkedeFilerF11())

        cyclusGui.Add("Button", "x25 y498 w410 h32 -Theme +Background3A3A3A", "🔗 Lagre kopiert lenke (URL) i Notepad").OnEvent("Click", (*) => LagreLenkeF11())

        cyclusGui.SetFont("s9 cAAAAAA Normal")
        cyclusGui.Add("Text", "x25 y538 w410 h32", "Tips: Dobbeltklikk kopierer passord. 'Lås' gjør at ALLE nye filer som dukker opp får samme passord automatisk, helt til du trykker 'lås opp'.")

        cyclusGui.Add("Button", "x25 y578 w410 h35 -Theme +Background222222", "✖ Lukk Register").OnEvent("Click", (*) => (cyclusGui.Destroy(), cyclusGui := ""))

        lvCyclus.OnEvent("ItemFocus", VisPassordTooltipF11)
        lvCyclus.OnEvent("DoubleClick", KopierPassordF11)

        cyclusGui.OnEvent("Close",  (*) => (cyclusGui := ""))
        cyclusGui.OnEvent("Escape", (*) => (cyclusGui.Destroy(), cyclusGui := ""))

        OppdatertCyclusPanelLiveF11()
        cyclusGui.Show("W460 H641 Center")
    }
}

; ==============================================================================
; TEMA-STØTTE — F10 kan fortsatt style F11-panelet live via Themes/StlIdx
; ==============================================================================
UpdStl11(t) {
    global Themes, StlIdx, cyclusGui, lvCyclus
    static o := 0
    try if (IsObject(cyclusGui) and WinExist("ahk_id " cyclusGui.Hwnd) and IsSet(StlIdx) and (t or StlIdx != o)) {
        o := StlIdx, st := Themes[StlIdx]
        cyclusGui.BackColor := st.bg
        if (IsSet(lvCyclus) and IsObject(lvCyclus))
            lvCyclus.Opt("+Background" st.ft " c" st.fg)
        WinRedraw("ahk_id " cyclusGui.Hwnd)
    }
}

OppdatertCyclusPanelLiveF11() {
    global lvCyclus, CyclusKart
    try {
        if !IsSet(lvCyclus) or !IsObject(lvCyclus)
            return
        lvCyclus.Delete()
        for idx, element in CyclusKart {
            lastNed := element.HasOwnProp("lastNed") and element.lastNed
            visPas := lastNed
                    ? "⬇️ Laster ned..."
                    : (element.p = "VENTER_PÅ_MATING" or element.p = "") ? "⏳ Venter på passord..."
                    : element.p
            lvCyclus.Add(, element.f, visPas)
        }
        lvCyclus.ModifyCol(1, 280)
        lvCyclus.ModifyCol(2, 130)
    }
}

FjernValgtFraKøF11() {
    global lvCyclus, CyclusKart
    if !IsSet(lvCyclus) or !IsObject(lvCyclus)
        return
    valgtRad := lvCyclus.GetNext()
    if (valgtRad = 0) {
        ToolTip("⚠️ Ingen rad valgt!")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    valgtFilnavn := lvCyclus.GetText(valgtRad, 1)
    nyKø := []
    for idx, element in CyclusKart {
        if (element.f != valgtFilnavn)
            nyKø.Push(element)
    }
    CyclusKart := nyKø
    OppdatertCyclusPanelLiveF11()
}

TømHeleKøenF11() {
    global CyclusKart, CyclusTeller, GjeldendeVenteFil
    if (MsgBox("Er du sikker på at du vil tømme hele køen?", "Bekreft", "YesNo Icon!") = "No")
        return
    CyclusKart := []
    CyclusTeller := 0
    GjeldendeVenteFil := ""
    OppdatertCyclusPanelLiveF11()
}

SettPassordManueltF11() {
    global lvCyclus, CyclusKart, cyclusGui
    if !IsSet(lvCyclus) or !IsObject(lvCyclus)
        return
    valgtRad := lvCyclus.GetNext()
    if (valgtRad = 0) {
        ToolTip("⚠️ Ingen rad valgt!")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    valgtFilnavn := lvCyclus.GetText(valgtRad, 1)
    for idx, element in CyclusKart {
        if (element.f == valgtFilnavn) {
            nyttPassord := InputBox("Fil: " element.f "`n`nSkriv inn passord:", "Sett passord", "w450 h180" EierAlternativF11()).Value
            if (nyttPassord != "")
                element.p := nyttPassord
            break
        }
    }
    OppdatertCyclusPanelLiveF11()
}

; ==============================================================================
; 🔗 SETT SAMME PASSORD PÅ FLERE VALGTE FILER (F11-KØ-GRUPPE)
; Marker flere rader med Ctrl+klikk eller Shift+klikk, så settes ETT passord
; på ALLE de valgte filene samtidig — nyttig når en gruppe filer deler passord.
; ==============================================================================
SettPassordFlereF11() {
    global lvCyclus, CyclusKart, cyclusGui
    if !IsSet(lvCyclus) or !IsObject(lvCyclus)
        return

    valgteNavn := []
    rad := 0
    while (rad := lvCyclus.GetNext(rad))
        valgteNavn.Push(lvCyclus.GetText(rad, 1))

    if (valgteNavn.Length = 0) {
        ToolTip("⚠️ Ingen filer valgt! Ctrl/Shift-klikk for å velge flere.")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    melding := valgteNavn.Length = 1
        ? "Fil: " valgteNavn[1] "`n`nSkriv inn passord:"
        : valgteNavn.Length " filer valgt.`n`nSkriv inn passord som skal brukes på ALLE:"
    nyttPassord := InputBox(melding, "Sett passord på " valgteNavn.Length " fil(er)", "w450 h180" EierAlternativF11()).Value
    if (nyttPassord = "")
        return

    navnKart := Map()
    for idx, navn in valgteNavn
        navnKart[navn] := true

    antallSatt := 0
    for idx, element in CyclusKart {
        if (navnKart.Has(element.f)) {
            element.p := nyttPassord
            antallSatt++
        }
    }

    OppdatertCyclusPanelLiveF11()
    SoundPlay("*64")
    ToolTip("🔗 Passord satt på " antallSatt " fil(er)!")
    SetTimer(() => ToolTip(), -2500)
}

; ==============================================================================
; 🔒 LÅS/LÅS OPP PASSORD FOR NYE FILER
; Når aktiv: alle NYE filer som mappevakten oppdager får dette passordet
; automatisk med en gang, uten at du trenger å mate dem manuelt.
; Trykk knappen igjen for å låse opp (nye filer går tilbake til "venter").
; ==============================================================================
VekslLåstPassordF11() {
    global LåstPassordAktiv, LåstPassordVerdi, lockBtnF11, cyclusGui

    if (LåstPassordAktiv) {
        LåstPassordAktiv := false
        LåstPassordVerdi := ""
        try lockBtnF11.Text := "🔓 Lås passord for nye filer"
        ToolTip("🔓 Låsing avsluttet — nye filer venter på passord som normalt.")
        SetTimer(() => ToolTip(), -2500)
    } else {
        nyttPassord := InputBox("Skriv inn passordet som skal brukes automatisk`npå ALLE nye filer som dukker opp i køen,`nhelt til du trykker 'lås opp':", "Lås passord for nye filer", "w450 h190" EierAlternativF11()).Value
        if (nyttPassord = "")
            return
        LåstPassordAktiv := true
        LåstPassordVerdi := nyttPassord
        try lockBtnF11.Text := "🔒 Låst: " nyttPassord
        SoundPlay("*64")
        ToolTip("🔒 Låst! Alle nye filer får dette passordet automatisk.")
        SetTimer(() => ToolTip(), -2500)
    }
}

; ==============================================================================
; 📋 KOPIER ALLE PASSORD FRA EN BESTEMT "RUNDE" (utpakkingsøkt)
; Leser den auto-lagrede Notepad-loggen og henter ut alle passord som ble
; lagret under "=== RUNDE N ===" for runden du oppgir.
; ==============================================================================
KopierRundePassordF11() {
    global PassordNotatFil, RundeTeller, cyclusGui

    if !FileExist(PassordNotatFil) {
        MsgBox("Ingen passord er lagret ennå. Kjør en utpakking (F3) først.", "Ingen data", 48)
        return
    }

    rundeNr := InputBox("Hvilken runde vil du kopiere passord fra?`n`n(Siste runde så langt: " RundeTeller ")", "Kopier passord fra runde", "w400 h160" EierAlternativF11()).Value
    if (rundeNr = "")
        return

    innhold := FileRead(PassordNotatFil, "UTF-8")
    linjer := StrSplit(innhold, "`n", "`r")

    innenforRunde := false
    treff := []
    for idx, linje in linjer {
        if RegExMatch(linje, "^=== RUNDE (\d+) ===", &m) {
            innenforRunde := (m[1] = rundeNr)
            continue
        }
        if (innenforRunde and RegExMatch(linje, "Passord:\s*(.+)$", &pm))
            treff.Push(Trim(pm[1]))
    }

    if (treff.Length = 0) {
        MsgBox("Fant ingen lagrede passord for runde " rundeNr ".", "Ingen treff", 48)
        return
    }

    A_Clipboard := ""
    for idx, pw in treff
        A_Clipboard .= pw "`r`n"

    SoundPlay("*64")
    ToolTip("📋 Kopierte " treff.Length " passord fra runde " rundeNr "!")
    SetTimer(() => ToolTip(), -2500)
}

; ==============================================================================
; AUTO-LAGRING — kalles fra utpakkingsmotoren (F3) for HVER fil som blir
; korrekt pakket ut. Grupperer lagringen under "=== RUNDE N ===" slik at man
; kan kopiere ut alle passord for en gitt utpakkingsøkt samlet.
; ==============================================================================
LagreAutoPassordF11(navn, passord, runde) {
    global PassordNotatFil, RundeHarSkrevetHode
    try {
        if !FileExist(PassordNotatFil)
            FileAppend("=== LAGREDE PASSORD (auto-lagret ved vellykket utpakking) ===`r`n", PassordNotatFil, "UTF-8")
        if !RundeHarSkrevetHode.Has(runde) {
            FileAppend("`r`n=== RUNDE " runde " ===`r`n", PassordNotatFil, "UTF-8")
            RundeHarSkrevetHode[runde] := true
        }
        FileAppend("FIL: " navn " -> OK med tilordnet passord | Passord: " passord "`r`n", PassordNotatFil, "UTF-8")
    }
}

; ==============================================================================
; 📝 ÅPNE NOTEPAD-LOGGEN DIREKTE FRA F11
; ==============================================================================
ÅpnePassordNotatF11() {
    global PassordNotatFil
    try {
        if !FileExist(PassordNotatFil)
            FileAppend("=== LAGREDE PASSORD (auto-lagret ved vellykket utpakking) ===`r`n", PassordNotatFil, "UTF-8")
        Run('notepad.exe "' PassordNotatFil '"')
    } catch as e {
        MsgBox("Kunne ikke åpne Notepad-loggen:`n" e.Message, "Feil", 16)
    }
}

; ==============================================================================
; DOBBELTKLIKK PÅ EN RAD — KOPIERER PASSORDET TIL UTKLIPPSTAVLEN
; (Kan deretter limes inn med Ctrl+V hvor som helst — Notepad, Chrome, WinRAR osv.)
; ==============================================================================
KopierPassordF11(ctrl, rad) {
    global CyclusKart
    try {
        if (rad = 0 or rad > CyclusKart.Length)
            return
        element := CyclusKart[rad]
        if (element.p = "VENTER_PÅ_MATING" or element.p = "") {
            ToolTip("⚠️ Denne filen har ikke fått passord enda!")
            SetTimer(() => ToolTip(), -2000)
            return
        }
        A_Clipboard := element.p
        SoundPlay("*64")
        ToolTip("📋 Passord kopiert! Lim inn med Ctrl+V.")
        SetTimer(() => ToolTip(), -2000)
    }
}

; ==============================================================================
; VIS FULLT PASSORD SOM TOOLTIP NÅR EN RAD MARKERES/HOLDES OVER
; ==============================================================================
VisPassordTooltipF11(ctrl, rad) {
    global CyclusKart
    try {
        if (rad = 0 or rad > CyclusKart.Length)
            return
        element := CyclusKart[rad]
        if (element.p = "VENTER_PÅ_MATING" or element.p = "")
            return
        ToolTip("🔑 " element.f "`n" element.p)
        SetTimer(() => ToolTip(), -3000)
    }
}

; ==============================================================================
; 🔁 PRØV MISLYKKEDE FILER FRA SISTE RUNDE PÅ NYTT
; Mislykkede filer forblir i F11-køen (med "venter på passord") etter en
; feilet utpakking. Denne knappen markerer/velger dem, og lar deg kjøre F3
; på nytt så snart du har rettet opp passordet.
; ==============================================================================
PrøvMislykkedeFilerF11() {
    global SisteFeiledeFiler, CyclusKart, lvCyclus

    if (SisteFeiledeFiler.Length = 0) {
        MsgBox("Ingen filer har feilet i siste runde ennå.", "Ingen mislykkede filer", 64)
        return
    }

    manglerPassord := 0
    for idx, navn in SisteFeiledeFiler {
        for idx2, element in CyclusKart {
            if (element.f == navn and (element.p = "VENTER_PÅ_MATING" or element.p = ""))
                manglerPassord++
        }
    }

    if (manglerPassord > 0) {
        MsgBox(manglerPassord " av " SisteFeiledeFiler.Length " mislykkede fil(er) venter fortsatt på passord.`n`nMat inn riktig passord (manuelt, Ctrl+Shift+C, eller '🔗 Sett samme passord på valgte'), og trykk deretter F3/Utpakk-knappen for å prøve på nytt.", "Mangler passord", 48)
        return
    }

    if (MsgBox(SisteFeiledeFiler.Length " fil(er) fra siste runde har passord klart. Kjøre utpakking på nytt nå?", "Prøv på nytt", "YesNo Icon?") = "Yes")
        TriggerUtpakkingLive()
}

; ==============================================================================
; 🔗 LAGRE KOPIERT LENKE (URL) I NOTEPAD
; Kopier en URL i nettleseren (f.eks. Ctrl+L for å merke adressefeltet, så
; Ctrl+C for å kopiere), trykk så denne knappen (eller hurtigtasten satt i F1).
; Du blir spurt om et navn på lenken, og "Navn -> URL" lagres i Notepad-loggen.
; ==============================================================================
LagreLenkeF11() {
    global PassordNotatFil, cyclusGui

    lenkeTekst := Trim(String(A_Clipboard))
    if (lenkeTekst = "" or !RegExMatch(lenkeTekst, "i)^https?://")) {
        A_Clipboard := ""
        Sleep(150)
        Send("^c")
        if !ClipWait(1.2, 1) {
            ToolTip("⚠️ Ingen lenke funnet på utklippstavlen! Kopier URL-en først (Ctrl+L, Ctrl+C).")
            SetTimer(() => ToolTip(), -3000)
            return
        }
        lenkeTekst := Trim(String(A_Clipboard))
    }

    if (lenkeTekst = "" or !RegExMatch(lenkeTekst, "i)^https?://")) {
        ToolTip("⚠️ Det som ble kopiert ser ikke ut som en gyldig URL.")
        SetTimer(() => ToolTip(), -3000)
        return
    }

    navn := InputBox("Lenke som ble kopiert:`n" lenkeTekst "`n`nSkriv inn et navn for lenken:", "Lagre lenke", "w450 h190" EierAlternativF11()).Value
    if (navn = "")
        navn := "Uten navn"

    try {
        if !FileExist(PassordNotatFil)
            FileAppend("=== LAGREDE PASSORD (auto-lagret ved vellykket utpakking) ===`r`n", PassordNotatFil, "UTF-8")
        FileAppend("LENKE: " navn " -> " lenkeTekst "`r`n", PassordNotatFil, "UTF-8")
        Run('notepad.exe "' PassordNotatFil '"')
        SoundPlay("*64")
        ToolTip("🔗 Lenke lagret i Notepad!")
        SetTimer(() => ToolTip(), -2000)
    } catch as e {
        MsgBox("Kunne ikke lagre lenken:`n" e.Message, "Feil", 16)
    }
}

; ==============================================================================
; 💾 LAGRE VALGT PASSORD (NAVN + PASSORD) I EN NOTEPAD-FIL
; ==============================================================================
LagrePassordINotepadF11() {
    global lvCyclus, CyclusKart, PassordNotatFil
    if !IsSet(lvCyclus) or !IsObject(lvCyclus)
        return
    valgtRad := lvCyclus.GetNext()
    if (valgtRad = 0) {
        ToolTip("⚠️ Ingen rad valgt!")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    valgtFilnavn := lvCyclus.GetText(valgtRad, 1)
    for idx, element in CyclusKart {
        if (element.f == valgtFilnavn) {
            if (element.p = "VENTER_PÅ_MATING" or element.p = "") {
                ToolTip("⚠️ Denne filen har ikke fått passord enda!")
                SetTimer(() => ToolTip(), -2000)
                return
            }
            try {
                if !FileExist(PassordNotatFil)
                    FileAppend("=== LAGREDE PASSORD (auto-lagret ved vellykket utpakking) ===`r`n", PassordNotatFil, "UTF-8")
                FileAppend("FIL: " element.f " -> OK med tilordnet passord | Passord: " element.p "`r`n", PassordNotatFil, "UTF-8")
                Run('notepad.exe "' PassordNotatFil '"')
                SoundPlay("*64")
                ToolTip("💾 Lagret i Notepad!")
                SetTimer(() => ToolTip(), -2000)
            } catch as e {
                MsgBox("Kunne ikke lagre passordet:`n" e.Message, "Feil", 16)
            }
            break
        }
    }
}

; ==============================================================================
; CTRL+SHIFT+C — MATER PASSORD FRA MARKERT TEKST TIL ØVERSTE LEDIGE FIL I KØEN
; ==============================================================================
^+c:: {
    global CyclusKart, GjeldendeVenteFil

    A_Clipboard := ""
    Sleep(150)
    Send("^c")
    if !ClipWait(1.2, 1) {
        ToolTip("⚠️ Ingen passord detektert!")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    rentPassord := Trim(String(A_Clipboard))
    if (rentPassord == "") {
        ToolTip("⚠️ Ugyldig tekst detektert!")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    matingUtført := false
    nesteFilKlar := ""

    for idx, element in CyclusKart {
        if (element.p == "VENTER_PÅ_MATING" or element.p == "") {
            element.p := rentPassord
            matingUtført := true
            SoundPlay("*64")
            break
        }
    }

    for idx, element in CyclusKart {
        if (element.p == "VENTER_PÅ_MATING" or element.p == "") {
            nesteFilKlar := element.f
            break
        }
    }

    if (matingUtført) {
        ToolTip(nesteFilKlar != "" ? "✅ Matet! 🚀 Neste: " nesteFilKlar : "🟢 Alle filer har passord!")
        SetTimer(() => ToolTip(), -2500)
        GjeldendeVenteFil := nesteFilKlar
        OppdatertCyclusPanelLiveF11()
    } else {
        ToolTip("✅ Alle filer i køen har allerede passord!")
        SetTimer(() => ToolTip(), -2000)
    }
}

; ==============================================================================
; MAPPEVAKT — Skanner SrcM (samme mappe som F5 "Endre Mappe" peker på)
; Legger automatisk til nye arkivfiler i F11-køen, klare for passord.
; ==============================================================================
UtførMappeSkanningF11() {
    global CyclusKart, GjeldendeVenteFil, CyclusTeller, SrcM, StørrelseSjekkKart, LåstPassordAktiv, LåstPassordVerdi

    if (!IsSet(SrcM) or SrcM == "" or !DirExist(SrcM))
        return

    filerSettDenneRunden := Map()
    nyeFiler := false

    Loop Files, SrcM "\*.*" {
        ; Er dette en kjent midlertidig nedlastingsendelse? Da laster filen fortsatt ned.
        erMidlertidigEndelse := RegExMatch(A_LoopFileExt, "i)crdwnload|crdownload|tmp|part|download|opdownload|\!ut|\!qb|aria2")

        ; Finn det "ekte" filnavnet uten midlertidig endelse, slik at vi kan sjekke
        ; om DET er et arkiv (f.eks. "film.rar.crdownload" -> "film.rar")
        arbeidsNavn := A_LoopFileName
        if (erMidlertidigEndelse)
            SplitPath(arbeidsNavn, , , , &arbeidsNavn)   ; fjerner f.eks. ".crdownload"

        SplitPath(arbeidsNavn, , , &ekteEndelse, &BareNavn)  ; ekteEndelse = f.eks. "rar", BareNavn = uten noen endelse

        if !RegExMatch(ekteEndelse, "i)^rar$|^zip$|^7z$|^1$|^001$")
            continue
        if RegExMatch(arbeidsNavn, "i)\.part(?:0[2-9]|[2-9]\d*)\.rar$")
            continue
        if RegExMatch(ekteEndelse, "^(?:00[2-9]|0[1-9]\d|[1-9]\d{2,})$")
            continue

        filerSettDenneRunden[A_LoopFileName] := true

        ; Størrelsesstabilitet — samme prinsipp som i mappevakten: filen må ha lik
        ; størrelse to skanninger på rad før den regnes som ferdig nedlastet.
        erFerdig := false
        gjeldendeStørrelse := A_LoopFileSize
        if StørrelseSjekkKart.Has(A_LoopFileName) {
            erFerdig := (StørrelseSjekkKart[A_LoopFileName] == gjeldendeStørrelse)
        }
        StørrelseSjekkKart[A_LoopFileName] := gjeldendeStørrelse

        eksisterendeElement := ""
        for idx, element in CyclusKart {
            if (element.f == BareNavn) {
                eksisterendeElement := element
                break
            }
        }

        if (eksisterendeElement == "") {
            tildeltPassord := (LåstPassordAktiv and LåstPassordVerdi != "") ? LåstPassordVerdi : "VENTER_PÅ_MATING"
            CyclusKart.Push({f: BareNavn, p: tildeltPassord, lastNed: !erFerdig})
            GjeldendeVenteFil := (tildeltPassord = "VENTER_PÅ_MATING") ? BareNavn : GjeldendeVenteFil
            CyclusTeller++
            nyeFiler := true
        } else if (erFerdig and eksisterendeElement.lastNed) {
            eksisterendeElement.lastNed := false
            nyeFiler := true
        }
    }

    for filnavn in StørrelseSjekkKart.Clone() {
        if !filerSettDenneRunden.Has(filnavn)
            StørrelseSjekkKart.Delete(filnavn)
    }

    ; Fjern rader for filer som ikke lenger finnes i mappen (slettet/flyttet/pakket ut)
    if (CyclusKart.Length > 0) {
        beholdesListe := []
        køEndret := false
        for idx, element in CyclusKart {
            finnesFortsatt := false
            Loop Files, SrcM "\" element.f ".*" {
                finnesFortsatt := true
                break
            }
            if (finnesFortsatt)
                beholdesListe.Push(element)
            else
                køEndret := true
        }
        if (køEndret) {
            CyclusKart := beholdesListe
            nyeFiler := true
        }
    }

    if (nyeFiler)
        OppdatertCyclusPanelLiveF11()
}
