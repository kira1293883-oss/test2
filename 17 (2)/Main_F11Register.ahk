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
global BackupFilF11       := A_Desktop "\F11_Register_Backup.txt"
global RundeTeller         := 0     ; Øker med 1 for hver F3-utpakkingsøkt ("Runde 1", "Runde 2" ...)
global RundeHarSkrevetHode := Map() ; Husker om vi har skrevet "=== RUNDE N ===" for denne runden ennå
global LåstPassordAktiv    := false ; Når true: nye filer som oppdages får automatisk LåstPassordVerdi
global LåstPassordVerdi    := ""
global lockBtnF11          := ""
global SisteFeiledeFiler   := []   ; Filnavn som feilet i siste F3-runde
global SistMatetFilF11     := ""   ; Filen som sist fikk passord via Ctrl+Shift+C (for Ctrl+Shift+L-kobling)
global LagreUrlAktiv       := true ; PÅ/AV-bryter: skal URL lagres sammen med navn+passord?
global urlToggleBtnF11     := ""

SetTimer(UtførMappeSkanningF11, CyclusSkannIntervallms)

; InputBox() i AHK v2 støtter IKKE "Owner" som opsjon (det gir "Invalid option").
; Denne hjelperen tvinger i stedet InputBox-vinduet fremst og øverst ved å
; vente på at det dukker opp (etter tittelen) og sette det AlwaysOnTop.
VisInputBoxF11(prompt, tittel, opts := "", standard := "") {
    SetTimer(() => TvingVinduFremF11(tittel), -120)
    return InputBox(prompt, tittel, opts, standard)
}

TvingVinduFremF11(tittel) {
    try {
        if WinWait(tittel, , 1) {
            WinSetAlwaysOnTop(true, tittel)
            WinActivate(tittel)
        }
    }
}

; ==============================================================================
; F11 — ÅPNE/LUKK REGISTERPANEL
; ==============================================================================
TriggerF11Register() {
    global cyclusGui, lvCyclus, CyclusSkannIntervallms, Themes, StlIdx, lockBtnF11, LåstPassordAktiv, LåstPassordVerdi, urlToggleBtnF11, LagreUrlAktiv
    try {
        if IsObject(cyclusGui) and WinExist("ahk_id " cyclusGui.Hwnd) {
            cyclusGui.Destroy(), cyclusGui := ""
            return
        }
        st := Themes[StlIdx]
        cyclusGui := Gui("-Caption -Border +AlwaysOnTop")
        cyclusGui.BackColor := st.bg
        cyclusGui.MarginX := 20, cyclusGui.MarginY := 20
        cyclusGui.SetFont("s9.5 c" st.fg " Bold", "Segoe UI")
        cyclusGui.Add("Text", "x20 y20 w480 h22", "🔑 Passordregister — klikk en celle for å kopiere")

        cyclusGui.SetFont("s8.5 cD0D0D0 Normal", "Segoe UI")
        lvCyclus := cyclusGui.Add("ListView",
            "x20 y50 w580 h220 +VScroll +HScroll +0x2000000 Background" st.ft " c" st.fg " Grid",
            ["Filnavn", "Passord", "URL"])

        cyclusGui.SetFont("s8.5 cWhite")
        cyclusGui.Add("Button", "x20  y280 w186 h28 -Theme +Background3A3A3A", "🗑 Fjern valgt").OnEvent("Click", (*) => FjernValgtFraKøF11())
        cyclusGui.Add("Button", "x214 y280 w186 h28 -Theme +Background3A3A3A", "✏️ Sett passord").OnEvent("Click", (*) => SettPassordManueltF11())
        cyclusGui.Add("Button", "x408 y280 w192 h28 -Theme +Background3A3A3A", "🔗 Sett URL").OnEvent("Click", (*) => SettLenkeForValgtF11())

        cyclusGui.Add("Button", "x20 y314 w580 h28 -Theme +Background3A3A3A", "🔗 Sett samme passord på valgte (Ctrl/Shift-klikk)").OnEvent("Click", (*) => SettPassordFlereF11())

        lockBtnF11 := cyclusGui.Add("Button", "x20 y348 w286 h28 -Theme +Background3A3A3A", LåstPassordAktiv ? "🔒 Låst: " LåstPassordVerdi : "🔓 Lås passord for nye filer")
        lockBtnF11.OnEvent("Click", (*) => VekslLåstPassordF11())
        cyclusGui.Add("Button", "x314 y348 w286 h28 -Theme +Background3A3A3A", "📋 Kopier passord fra runde").OnEvent("Click", (*) => KopierRundePassordF11())

        cyclusGui.Add("Button", "x20 y382 w286 h28 -Theme +Background3A3A3A", "🧹 Tøm kø").OnEvent("Click", (*) => TømHeleKøenF11())
        cyclusGui.Add("Button", "x314 y382 w286 h28 -Theme +Background3A3A3A", "🔁 Prøv mislykkede på nytt").OnEvent("Click", (*) => PrøvMislykkedeFilerF11())

        ; ⋯ Mer — sjeldnere brukte funksjoner samlet i én knapp for et ryddigere panel
        urlToggleBtnF11 := cyclusGui.Add("Button", "x20 y416 w580 h28 -Theme +Background2A2A2A", "⋯ Mer  (Notepad-logg · lagre lenke · URL-lagring: " (LagreUrlAktiv ? "PÅ" : "AV") ")")
        urlToggleBtnF11.OnEvent("Click", (*) => VisMerMenyF11())

        cyclusGui.SetFont("s8 cAAAAAA Normal")
        cyclusGui.Add("Text", "x20 y452 w580 h32", "Ctrl+Shift+C mater passord og fanger automatisk URL fra adressefeltet ~1 sek etterpå. Passordet ligger klart på utklippstavlen.")

        cyclusGui.Add("Button", "x20 y488 w580 h32 -Theme +Background222222", "✖ Lukk").OnEvent("Click", (*) => (cyclusGui.Destroy(), cyclusGui := ""))

        lvCyclus.OnEvent("Click", KlikkKopierKolonneF11)

        cyclusGui.OnEvent("Close",  (*) => (cyclusGui := ""))
        cyclusGui.OnEvent("Escape", (*) => (cyclusGui.Destroy(), cyclusGui := ""))

        OppdatertCyclusPanelLiveF11()
        cyclusGui.Show("W620 H540 Center")
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
            visUrl := (element.HasOwnProp("url") and element.url != "") ? element.url : ""
            lvCyclus.Add(, element.f, visPas, visUrl)
        }
        lvCyclus.ModifyCol(1, 220)
        lvCyclus.ModifyCol(2, 130)
        lvCyclus.ModifyCol(3, 250)
    }
    LagreBackupF11()
}

; ==============================================================================
; 💾 AUTOMATISK SIKKERHETSKOPI AV PASSORDREGISTERET
; Skriver hele CyclusKart til en enkel tekstfil (ett felt per linje, "‖" som
; skilletegn) hver gang registeret endres — pluss en periodisk timer som
; sikkerhetsnett i tilfelle en endring skjer uten å gå via den vanlige
; oppdateringsfunksjonen. Filen kan leses tilbake med GjenopprettBackupF11().
; ==============================================================================
LagreBackupF11() {
    global CyclusKart, BackupFilF11
    try {
        innhold := ""
        for idx, element in CyclusKart {
            p := element.p
            url := element.HasOwnProp("url") ? element.url : ""
            lastNed := (element.HasOwnProp("lastNed") and element.lastNed) ? "1" : "0"
            innhold .= element.f "‖" p "‖" url "‖" lastNed "`n"
        }
        FileDelete(BackupFilF11)
    } catch {
        ; Filen fantes ikke fra før — helt greit, fortsett bare.
    }
    try FileAppend(innhold, BackupFilF11, "UTF-8")
}

; Slås på med jevne mellomrom som et sikkerhetsnett, i tillegg til at
; LagreBackupF11() allerede kalles ved hver eneste endring i registeret.
SetTimer(LagreBackupF11, 60000)

; ==============================================================================
; ♻️ GJENOPPRETT SISTE SESJON FRA SIKKERHETSKOPIEN
; Leser F11_Register_Backup.txt og fyller inn passord/URL for filer som
; FORTSATT finnes i CyclusKart (f.eks. etter en krasj/restart der mappeskanning
; allerede har funnet filene på nytt, men med "VENTER_PÅ_MATING"). Overskriver
; ALDRI et passord som allerede er satt — kun tomme/ventende felt fylles inn.
; ==============================================================================
GjenopprettBackupF11() {
    global CyclusKart, BackupFilF11
    if !FileExist(BackupFilF11) {
        ToolTip("⚠️ Ingen sikkerhetskopi funnet enda.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    try {
        innhold := FileRead(BackupFilF11, "UTF-8")
    } catch {
        ToolTip("⚠️ Kunne ikke lese sikkerhetskopien.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    gjenopprettet := 0
    Loop Parse, innhold, "`n", "`r" {
        if (A_LoopField = "")
            continue
        deler := StrSplit(A_LoopField, "‖")
        if (deler.Length < 2)
            continue
        bF := deler[1], bP := deler[2], bUrl := (deler.Length >= 3) ? deler[3] : ""

        for idx, element in CyclusKart {
            if (element.f != bF)
                continue
            if (element.p = "VENTER_PÅ_MATING" or element.p = "") and (bP != "VENTER_PÅ_MATING" and bP != "") {
                element.p := bP
                gjenopprettet++
            }
            if (!element.HasOwnProp("url") or element.url = "") and (bUrl != "") {
                element.url := bUrl
            }
            break
        }
    }

    OppdatertCyclusPanelLiveF11()
    ToolTip(gjenopprettet > 0 ? "♻️ Gjenopprettet " gjenopprettet " passord fra sikkerhetskopi!" : "ℹ️ Ingen filer trengte gjenoppretting.")
    SetTimer(() => ToolTip(), -2500)
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
            nyttPassord := VisInputBoxF11("Fil: " element.f "`n`nSkriv inn passord:", "Sett passord", "w450 h180").Value
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
    nyttPassord := VisInputBoxF11(melding, "Sett passord på " valgteNavn.Length " fil(er)", "w450 h180").Value
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
        nyttPassord := VisInputBoxF11("Skriv inn passordet som skal brukes automatisk`npå ALLE nye filer som dukker opp i køen,`nhelt til du trykker 'lås opp':", "Lås passord for nye filer", "w450 h190").Value
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

    rundeNr := VisInputBoxF11("Hvilken runde vil du kopiere passord fra?`n`n(Siste runde så langt: " RundeTeller ")", "Kopier passord fra runde", "w400 h160").Value
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
LagreAutoPassordF11(navn, passord, runde, url := "", status := "OK med tilordnet passord") {
    global PassordNotatFil, RundeHarSkrevetHode, LagreUrlAktiv
    try {
        if !FileExist(PassordNotatFil)
            FileAppend("=== LAGREDE PASSORD (auto-lagret ved hver utpakking, OK og FEILET) ===`r`n", PassordNotatFil, "UTF-8")
        if !RundeHarSkrevetHode.Has(runde) {
            FileAppend("`r`n=== RUNDE " runde " ===`r`n", PassordNotatFil, "UTF-8")
            RundeHarSkrevetHode[runde] := true
        }
        linje := "FIL: " navn " -> " status " | Passord: " passord
        if (LagreUrlAktiv and url != "")
            linje .= " | URL: " url
        FileAppend(linje "`r`n", PassordNotatFil, "UTF-8")
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
; 🟢/⚪ SLÅ AV/PÅ OM URL SKAL LAGRES SAMMEN MED NAVN+PASSORD
; ==============================================================================
VekslUrlLagringF11() {
    global LagreUrlAktiv, urlToggleBtnF11
    LagreUrlAktiv := !LagreUrlAktiv
    try urlToggleBtnF11.Text := "⋯ Mer  (Notepad-logg · lagre lenke · URL-lagring: " (LagreUrlAktiv ? "PÅ" : "AV") ")"
    SoundPlay("*64")
    ToolTip(LagreUrlAktiv ? "🟢 URL lagres nå automatisk sammen med passord!" : "⚪ URL lagres ikke lenger.")
    SetTimer(() => ToolTip(), -2000)
}

; ==============================================================================
; ⋯ "MER"-MENY — samler de sjeldnere brukte handlingene i én liten meny,
; slik at hovedpanelet forblir ryddig og minimalistisk.
; ==============================================================================
VisMerMenyF11() {
    global LagreUrlAktiv
    merMeny := Menu()
    merMeny.Add("📝 Åpne Notepad-loggen", (*) => ÅpnePassordNotatF11())
    merMeny.Add("🔗 Lagre kopiert lenke (URL) i Notepad", (*) => LagreLenkeF11())
    merMeny.Add("💾 Lagre valgt i Notepad", (*) => LagrePassordINotepadF11())
    merMeny.Add()
    merMeny.Add((LagreUrlAktiv ? "🟢 URL-lagring: PÅ" : "⚪ URL-lagring: AV") " — klikk for å veksle", (*) => VekslUrlLagringF11())
    merMeny.Add()
    merMeny.Add("♻️ Gjenopprett siste sesjon fra sikkerhetskopi", (*) => GjenopprettBackupF11())
    merMeny.Show()
}

; ==============================================================================
; 📋 KLIKK EN CELLE I REGISTERET FOR Å KOPIERE NØYAKTIG DET SOM STÅR DER
; — akkurat som i Excel: hva du enn klikker på (Filnavn, Passord, URL),
; er det innholdet i AKKURAT den cellen som havner på utklippstavlen.
; ==============================================================================
KlikkKopierKolonneF11(ctrl, rad) {
    global CyclusKart
    try {
        if (rad = 0 or rad > CyclusKart.Length)
            return

        ; Alle klikk i raden kopierer passordet, uansett hvilken kolonne du
        ; klikker i (Filnavn/Passord/URL). Kolonnedeteksjon er droppet siden
        ; brukeren bare ønsker passordet uansett klikkposisjon.
        kolonne := 1
        element := CyclusKart[rad]
        hva := "Passord"

        if (element.p = "VENTER_PÅ_MATING" or element.p = "") {
            ToolTip("⚠️ Denne filen har ikke fått passord enda!")
            SetTimer(() => ToolTip(), -1800)
            return
        }

        verdi := element.p
        A_Clipboard := verdi

        ; Visuell bekreftelse: vis EKTE tekstmarkering (blå highlight rundt
        ; selve teksten, akkurat som et vanlig dobbeltklikk i f.eks. Notepad)
        ; ved å legge et lite tekstfelt nøyaktig oppå cellen et kort øyeblikk.
        VisTekstmarkeringF11(ctrl, rad, kolonne, verdi)

        SoundPlay("*64")
        ToolTip("📋 " hva " kopiert!")
        SetTimer(() => ToolTip(), -1500)
    }
}

; ==============================================================================
; 🔵 VIS EKTE TEKSTMARKERING (BLÅ) OPPÅ CELLEN SOM NETTOPP BLE KOPIERT.
; ListView kan ikke selv fargelegge tekst i én celle, så vi legger midlertidig
; et lite Edit-felt akkurat over cellen, fyller det med teksten, og markerer
; alt (EM_SETSEL) — det gir nøyaktig samme blå "dobbeltklikk-markert tekst"-
; utseende du kjenner fra Notepad/nettleser. Feltet forsvinner selv etter litt.
; ==============================================================================
VisTekstmarkeringF11(ctrl, rad, kolonne, tekst) {
    static popupGui := ""
    try if IsObject(popupGui)
        popupGui.Destroy()

    try {
        ; Hent cellens posisjon/størrelse via LVM_GETSUBITEMRECT (LVIR_BOUNDS)
        rc := Buffer(16, 0)
        NumPut("int", kolonne, rc, 0)   ; rc.left = hvilken subitem/kolonne
        NumPut("int", 0, rc, 4)         ; rc.top  = LVIR_BOUNDS
        SendMessage(0x1000 + 56, rad - 1, rc.Ptr, ctrl.Hwnd)   ; LVM_GETSUBITEMRECT

        venstre := NumGet(rc, 0, "int"), topp := NumGet(rc, 4, "int")
        høyre := NumGet(rc, 8, "int"), bunn := NumGet(rc, 12, "int")

        ; Windows-kvirk: LVM_GETSUBITEMRECT med subitem=0 gir bredden til HELE
        ; raden (alle kolonner), ikke bare kolonne 0. Klem derfor høyre kant
        ; til faktisk kolonne 0-bredde når det er "Filnavn"-kolonnen.
        if (kolonne = 0) {
            col1Bredde := SendMessage(0x101D, 0, 0, ctrl.Hwnd)   ; LVM_GETCOLUMNWIDTH, kolonne 0
            høyre := venstre + col1Bredde
        }

        bredde := høyre - venstre, høyde := bunn - topp
        if (bredde < 10 or høyde < 8)
            return

        ; Klient-koordinater -> skjermkoordinater
        ptTL := Buffer(8, 0)
        NumPut("int", venstre, ptTL, 0), NumPut("int", topp, ptTL, 4)
        DllCall("ClientToScreen", "ptr", ctrl.Hwnd, "ptr", ptTL)
        skjX := NumGet(ptTL, 0, "int"), skjY := NumGet(ptTL, 4, "int")

        popupGui := Gui("-Caption +AlwaysOnTop +ToolWindow +Owner" ctrl.Gui.Hwnd)
        popupGui.BackColor := "1A1A1A"
        popupGui.MarginX := 0, popupGui.MarginY := 0
        popupGui.SetFont("s8.5 cWhite", "Segoe UI")
        ed := popupGui.Add("Edit", "x1 y1 w" (bredde - 2) " h" (høyde - 2) " -Theme ReadOnly -VScroll -HScroll Background1A1A1A", tekst)
        popupGui.Show("x" skjX " y" skjY " w" bredde " h" høyde " NoActivate")
        try ed.Focus()
        PostMessage(0x00B1, 0, -1, ed.Hwnd)   ; EM_SETSEL 0,-1 -> velg all tekst (blå markering)

        SetTimer(() => (IsObject(popupGui) ? (popupGui.Destroy(), popupGui := "") : 0), -1400)
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

    navn := VisInputBoxF11("Lenke som ble kopiert:`n" lenkeTekst "`n`nSkriv inn et navn for lenken:", "Lagre lenke", "w450 h190").Value
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
; 🌐 SETT LENKE (URL) FOR VALGT FIL MANUELT
; Fyller automatisk inn fra utklippstavlen hvis det ligger en gyldig URL der.
; ==============================================================================
SettLenkeForValgtF11() {
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

    forhåndsutfylt := ""
    utklipp := Trim(String(A_Clipboard))
    if RegExMatch(utklipp, "i)^https?://")
        forhåndsutfylt := utklipp

    for idx, element in CyclusKart {
        if (element.f == valgtFilnavn) {
            nyLenke := VisInputBoxF11("Fil: " element.f "`n`nLim inn/skriv URL for denne filen:", "Sett lenke (URL)", "w450 h180", forhåndsutfylt).Value
            if (nyLenke = "")
                return
            element.url := nyLenke
            OppdatertCyclusPanelLiveF11()
            SoundPlay("*64")
            ToolTip("🌐 Lenke satt for " element.f "!")
            SetTimer(() => ToolTip(), -2000)
            return
        }
    }
}

; ==============================================================================
; 💾 LAGRE VALGT PASSORD (NAVN + PASSORD) I EN NOTEPAD-FIL
; ==============================================================================
LagrePassordINotepadF11() {
    global lvCyclus, CyclusKart, PassordNotatFil, LagreUrlAktiv
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
                linje := "FIL: " element.f " -> OK med tilordnet passord | Passord: " element.p
                if (LagreUrlAktiv and element.HasOwnProp("url") and element.url != "")
                    linje .= " | URL: " element.url
                FileAppend(linje "`r`n", PassordNotatFil, "UTF-8")
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
; MATER PASSORD FRA MARKERT TEKST TIL ØVERSTE LEDIGE FIL I KØEN
; (Standard-tast: Ctrl+Shift+C — nå omprogrammerbar via F1-oppsettet)
; ==============================================================================
MaterPassordF11(*) {
    global CyclusKart, GjeldendeVenteFil, SistMatetFilF11

    A_Clipboard := ""
    Sleep(150)
    Send("^c")
    if !ClipWait(1.2, 1) {
        ToolTip("⚠️ Ingenting detektert!")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    kopiertTekst := Trim(String(A_Clipboard))
    if (kopiertTekst == "") {
        ToolTip("⚠️ Ugyldig tekst detektert!")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    ; 🔗 Hvis det som ble kopiert er en URL (f.eks. etter Ctrl+L i nettleseren),
    ; kobles den automatisk til filen som SIST fikk passord — samme tast
    ; (Ctrl+Shift+C) håndterer altså både passord OG URL automatisk.
    if RegExMatch(kopiertTekst, "i)^https?://") {
        if (SistMatetFilF11 = "") {
            ToolTip("⚠️ Ingen fil har fått passord ennå — mat et passord først.")
            SetTimer(() => ToolTip(), -2500)
            return
        }
        for idx, element in CyclusKart {
            if (element.f == SistMatetFilF11) {
                element.url := kopiertTekst
                SoundPlay("*64")
                ToolTip("🔗 URL koblet til: " element.f)
                SetTimer(() => ToolTip(), -2500)
                OppdatertCyclusPanelLiveF11()
                return
            }
        }
        ToolTip("⚠️ Fant ikke filen lenger i køen.")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    rentPassord := kopiertTekst

    matingUtført := false
    nesteFilKlar := ""

    for idx, element in CyclusKart {
        if (element.p == "VENTER_PÅ_MATING" or element.p == "") {
            element.p := rentPassord
            SistMatetFilF11 := element.f
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
        ; 🔗 Etter ~1 sekund: fang automatisk URL-en fra adressefeltet (Ctrl+L,
        ; Ctrl+C) og koble den til filen som nettopp fikk passord — helt uten
        ; at du trenger å trykke Ctrl+Shift+C en gang til.
        SetTimer(AutoFangUrlEtterPassordF11.Bind(SistMatetFilF11, rentPassord), -1000)
    } else {
        ToolTip("✅ Alle filer i køen har allerede passord!")
        SetTimer(() => ToolTip(), -2000)
    }
}

; ==============================================================================
; AUTOMATISK URL-FANGST — kjøres ~1 sekund etter at Ctrl+Shift+C matet et
; passord. Prøver å hente URL fra adressefeltet i det aktive vinduet.
; Passordet legges tilbake på utklippstavlen etterpå, slik at det fortsatt
; er klart til å limes inn et sted (f.eks. i et passordfelt).
; ==============================================================================
AutoFangUrlEtterPassordF11(filnavn, opprinneligPassord) {
    global CyclusKart, LagreUrlAktiv
    if !LagreUrlAktiv
        return
    try {
        Send("^l")
        Sleep(150)
        A_Clipboard := ""
        Send("^c")
        if !ClipWait(1.2, 1) {
            A_Clipboard := opprinneligPassord
            return
        }
        lenke := Trim(String(A_Clipboard))
        A_Clipboard := opprinneligPassord   ; passordet skal fortsatt være klart til innliming

        if !RegExMatch(lenke, "i)^https?://")
            return

        for idx, element in CyclusKart {
            if (element.f == filnavn) {
                element.url := lenke
                SoundPlay("*64")
                ToolTip("🔗 URL auto-fanget for: " element.f)
                SetTimer(() => ToolTip(), -2000)
                OppdatertCyclusPanelLiveF11()
                return
            }
        }
    }
}

; ==============================================================================
; CTRL+SHIFT+L — NOEN SEKUNDER ETTER CTRL+SHIFT+C: marker adressen i
; nettleseren (F.eks. Ctrl+L), trykk så Ctrl+Shift+L her. URL-en kobles
; automatisk til filen som SIST fikk passord tilordnet, og lagres i køen
; sammen med filnavn + passord — og havner i Notepad-loggen ved utpakking.
; ==============================================================================
^+l:: {
    global CyclusKart, SistMatetFilF11

    if (SistMatetFilF11 = "") {
        ToolTip("⚠️ Ingen fil er matet med passord ennå (bruk Ctrl+Shift+C først).")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    A_Clipboard := ""
    Sleep(150)
    Send("^c")
    if !ClipWait(1.2, 1) {
        ToolTip("⚠️ Ingen lenke detektert! Marker URL-en (Ctrl+L) og prøv igjen.")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    lenke := Trim(String(A_Clipboard))
    if (lenke = "" or !RegExMatch(lenke, "i)^https?://")) {
        ToolTip("⚠️ Det som ble kopiert ser ikke ut som en gyldig URL.")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    for idx, element in CyclusKart {
        if (element.f == SistMatetFilF11) {
            element.url := lenke
            SoundPlay("*64")
            ToolTip("🔗 Lenke koblet til: " element.f)
            SetTimer(() => ToolTip(), -2500)
            OppdatertCyclusPanelLiveF11()
            return
        }
    }
    ToolTip("⚠️ Fant ikke filen lenger i køen.")
    SetTimer(() => ToolTip(), -2500)
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
            CyclusKart.Push({f: BareNavn, p: tildeltPassord, lastNed: !erFerdig, url: ""})
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
