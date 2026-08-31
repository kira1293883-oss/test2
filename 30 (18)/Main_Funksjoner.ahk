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
LagreNyeHurtigtaster(g, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15) {
    global HK_Pause, HK_Extract, HK_Gui, HK_Speed, HK_Lock, HK_Round, HK_SaveNote, HK_Link, HK_Feed, HK_Notepad, HK_Folder, HK_UrlMeny, HK_ChromeRotate, HK_ChromeCount, HK_ChromePaste

    nyeVerdier := Map(
        "Pause-knapp", p1, "Utpakk-knapp", p2, "Passordregister", p3, "Farts-knapp", p4,
        "Lås passord", p5, "Kopier runde", p6, "Lagre i Notepad", p7, "Lagre lenke (URL)", p8,
        "Mate passord", p9, "Åpne Notepad-logg", p10, "Endre Mappe", p11, "URL-/Bannliste-meny", p12,
        "Send lenke (rotér)", p13, "Antall vinduer", p14, "Send merket tekst", p15)
    ; --- Gamle verdier i SAMME rekkefølge/navn som nyeVerdier, slik at vi vet
    ; nøyaktig hvilken GAMMEL tast som hører til hvert felt (brukes til å
    ; slå av bare DEN spesifikke gamle tasten når/hvis den nye faktisk virker). ---
    gamleVerdier := Map(
        "Pause-knapp", HK_Pause, "Utpakk-knapp", HK_Extract, "Passordregister", HK_Gui, "Farts-knapp", HK_Speed,
        "Lås passord", HK_Lock, "Kopier runde", HK_Round, "Lagre i Notepad", HK_SaveNote, "Lagre lenke (URL)", HK_Link,
        "Mate passord", HK_Feed, "Åpne Notepad-logg", HK_Notepad, "Endre Mappe", HK_Folder, "URL-/Bannliste-meny", HK_UrlMeny,
        "Send lenke (rotér)", HK_ChromeRotate, "Antall vinduer", HK_ChromeCount, "Send merket tekst", HK_ChromePaste)
    kallbaker := Map(
        "Pause-knapp", (*)=>CallPause(), "Utpakk-knapp", (*)=>TriggerUtpakkingLive(),
        "Passordregister", (*)=>TriggerF11Register(), "Farts-knapp", (*)=>TriggerF7Fartspanel(),
        "Lås passord", (*)=>VekslLåstPassordF11(), "Kopier runde", (*)=>KopierRundePassordF11(),
        "Lagre i Notepad", (*)=>LagrePassordINotepadF11(), "Lagre lenke (URL)", (*)=>LagreLenkeF11(),
        "Mate passord", (*)=>MaterPassordF11(), "Åpne Notepad-logg", (*)=>ÅpnePassordNotatF11(),
        "Endre Mappe", (*)=>F5_EndreMappeLive(), "URL-/Bannliste-meny", (*)=>TriggerF6UrlListeMeny(),
        "Send lenke (rotér)", (*)=>SendUrlTilChromeRotererF11(), "Antall vinduer", (*)=>VisAntallChromeVinduerF11(),
        "Send merket tekst", (*)=>SendValgtTekstAltP())

    ; --- KOLLISJONSSJEKK: to eller flere felt kan ikke peke på samme fysiske
    ; tast (f.eks. begge satt til F11). Uten denne sjekken ville begge feltene
    ; forsøke å registrere samme tast, og bare det SISTE feltet i rekkefølgen
    ; ville faktisk fungere — mens brukeren tror begge er aktive. Stopper HELE
    ; lagringen (ingenting endres) hvis dette oppdages, i stedet for å lagre
    ; noe halvveis feil. ---
    grupperPerTast := Map()
    for navn, verdi in nyeVerdier {
        nøkkel := Trim(StrLower(verdi))
        if (nøkkel = "")
            continue
        if !grupperPerTast.Has(nøkkel)
            grupperPerTast[nøkkel] := []
        grupperPerTast[nøkkel].Push(navn)
    }
    kollisjoner := ""
    for tast, navnListe in grupperPerTast {
        if (navnListe.Length > 1) {
            visningsTast := ""
            for i, n in navnListe
                visningsTast .= (i > 1 ? " + " : "") n
            kollisjoner .= visningsTast " (begge satt til '" tast "')`n"
        }
    }
    if (kollisjoner != "") {
        MsgBox("⚠️ To eller flere felt bruker SAMME tast — INGENTING ble lagret, alle gamle taster fortsetter å virke som før:`n`n" kollisjoner, "Tastekollisjon", 48)
        return
    }

    ; --- Registrer den NYE tasten FØRST for hvert felt. Bare HVIS den nye
    ; tasten faktisk lar seg registrere, slår vi av den GAMLE tasten for
    ; akkurat det feltet. Dette er rekkefølgen som betyr noe: forrige versjon
    ; slo av ALLE gamle taster FØR den prøvde å registrere de nye, så hvis
    ; ÉN ny tast feilet (f.eks. reservert av Windows/nettleseren, eller en
    ; skrivefeil), endte alle andre — inkludert F11-passordregisteret — opp
    ; fullstendig avslått med ingen vei tilbake før hele skjemaet ble rettet
    ; og lagret på nytt. Med denne rekkefølgen fortsetter GAMLE taster å
    ; virke helt til den NYE er bekreftet fungerende. ---
    feilet := ""
    for navn, nyTast in nyeVerdier {
        gammelTast := gamleVerdier[navn]
        try {
            Hotkey(nyTast, kallbaker[navn])
            if (nyTast != gammelTast and gammelTast != "") {
                try Hotkey(gammelTast, "Off")
            }
        } catch as e {
            feilet .= navn " ('" nyTast "'): " e.Message "`n"
        }
    }

    if (feilet != "") {
        MsgBox("⚠️ Følgende taster kunne IKKE registreres (de GAMLE tastene for akkurat disse feltene fortsetter å virke som før):`n`n" feilet "`nVanligste årsak: et annet program (f.eks. skjermopptaker, nettleser) bruker allerede denne tasten globalt, eller tasten er skrevet feil (bruk AHK-syntaks, f.eks. ^!f for Ctrl+Alt+F).", "Feil ved lagring av snarveier", 48)
        return
    }

    global HK_Pause := p1, HK_Extract := p2, HK_Gui := p3, HK_Speed := p4, HK_Lock := p5, HK_Round := p6, HK_SaveNote := p7, HK_Link := p8, HK_Feed := p9, HK_Notepad := p10, HK_Folder := p11, HK_UrlMeny := p12, HK_ChromeRotate := p13, HK_ChromeCount := p14, HK_ChromePaste := p15
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

; ==============================================================================
; SEKSJON 3: URL → CHROME MED ROTASJON PÅ 4 VINDUER (Ctrl+Alt+G)
; ------------------------------------------------------------------------------
; ⚠️ VIKTIG BEGRENSNING: AutoHotkey kan IKKE oppdage at musepekeren bare
; HVILER over en lenke inne i et annet program (Notepad, nettleser, PDF osv.)
; uten klikk — det krever tilgjengelighets-/skjermlesing (UI Automation) eller
; OCR, som ingen av programmene her eksponerer pålitelig. Den nærmeste
; praktiske erstatningen: MARKER lenketeksten der musa er (dra over den, eller
; dobbeltklikk/Ctrl+A i et lite tekstfelt), og trykk deretter Ctrl+Alt+G. Det
; kopierer markeringen og sender den til Chrome — akkurat som hover ville gitt,
; bare med ett lite tastetrykk i tillegg.
;
; ROTASJON: holder styr på ChromeRotasjonsMaks Chrome-vinduer og bytter mellom
; dem for hver nye lenke, i FAST rekkefølge (vindu 1 → 2 → 3 → 4 → 5 → 1 → ...).
; Mangler noen av dem, åpnes nye Chrome-vinduer automatisk slik at det alltid
; finnes nok å rotere mellom. Endre ChromeRotasjonsMaks under for å rotere på
; et annet antall enn 5.
; ==============================================================================
global ChromeRotasjonsIdx := 1
global ChromeRotasjonsMaks := 5

; --- Sorterer vindusliste etter numerisk Hwnd i stedet for z-rekkefølge ---
; VIKTIG: WinGetList returnerer vinduer i z-rekkefølge (sist aktiverte vindu
; øverst). Siden vi AKTIVERER et vindu hver gang vi sender en URL, hopper det
; vinduet til toppen av listen igjen ved neste kall — så en indeks-basert
; rotasjon uten denne sorteringen vil bare late som den roterer, mens den i
; praksis stadig treffer det samme (sist aktiverte) vinduet. Hwnd-verdien til
; et vindu endres derimot ALDRI så lenge vinduet forblir åpent, så å sortere
; på den gir en rekkefølge som er stabil på tvers av kall.
SorterVindusListeStabiltF11(liste) {
    sortert := liste.Clone()
    n := sortert.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            if (sortert[j] > sortert[j + 1]) {
                tmp := sortert[j]
                sortert[j] := sortert[j + 1]
                sortert[j + 1] := tmp
            }
        }
    }
    return sortert
}

; Denne hurtigtasten registreres nå dynamisk fra Main.ahk via HK_ChromeRotate,
; slik at den kan omprogrammeres i F1-panelet i stedet for å være hardkodet her.

; --- Ctrl+Alt+W (HK_ChromeCount): viser hvor mange Chrome-vinduer som er
; åpne akkurat nå, og hvilket nr. i rotasjonen som blir neste mål. Registreres
; også dynamisk fra Main.ahk via HK_ChromeCount. ---
VisAntallChromeVinduerF11() {
    global ChromeRotasjonsIdx, ChromeRotasjonsMaks
    chromeVinduer := SorterVindusListeStabiltF11(WinGetList("ahk_exe chrome.exe"))
    antall := chromeVinduer.Length
    ToolTip("🌐 " antall " Chrome-vindu(er) åpen(t) akkurat nå. Neste i rotasjon: vindu " ChromeRotasjonsIdx "/" ChromeRotasjonsMaks)
    SetTimer(() => ToolTip(), -2500)
}

SendUrlTilChromeRotererF11() {
    global ChromeRotasjonsIdx, ChromeRotasjonsMaks

    ; --- Slipp ev. modifikatortaster som fortsatt "henger igjen" fra selve
    ; hotkey-kombinasjonen FØR vi sender Ctrl+C, ellers kan f.eks. en
    ; hengende Alt gjøre om Ctrl+C til Ctrl+Alt+C, som ikke kopierer noe. ---
    Send("{Alt up}{Ctrl up}{Shift up}")
    Sleep(30)

    ; --- Kopier det som er markert akkurat nå (URL-en du har draget over) ---
    gammelPortefølje := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(1) {
        ToolTip("⚠️ Ingen tekst markert! Merk lenken (dra over den) og prøv igjen.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    lenke := Trim(A_Clipboard)
    A_Clipboard := gammelPortefølje

    if (!RegExMatch(lenke, "^[a-zA-Z][a-zA-Z0-9+.\-]*://") and !RegExMatch(lenke, "^www\.")) {
        ToolTip("⚠️ Det markerte ser ikke ut som en URL: " SubStr(lenke, 1, 60))
        SetTimer(() => ToolTip(), -2500)
        return
    }
    if (RegExMatch(lenke, "^www\."))
        lenke := "https://" lenke

    ; --- Sørg for at det finnes ChromeRotasjonsMaks Chrome-vinduer å rotere mellom ---
    chromeVinduer := SorterVindusListeStabiltF11(WinGetList("ahk_exe chrome.exe"))
    while (chromeVinduer.Length < ChromeRotasjonsMaks) {
        try Run('"' A_ProgramFiles '\Google\Chrome\Application\chrome.exe" --new-window')
        Sleep(900)
        chromeVinduer := SorterVindusListeStabiltF11(WinGetList("ahk_exe chrome.exe"))
        ; Sikkerhetsstopp mot evig løkke hvis Chrome ikke finnes/ikke starter
        if (chromeVinduer.Length = 0 and !FileExist(A_ProgramFiles "\Google\Chrome\Application\chrome.exe")) {
            ToolTip("⚠️ Fant ikke Chrome på standard sti. Sjekk installasjonen.")
            SetTimer(() => ToolTip(), -2500)
            return
        }
    }

    ; --- Velg neste vindu i rotasjonen (1..ChromeRotasjonsMaks, går rundt til 1 igjen) ---
    målHwnd := chromeVinduer[ChromeRotasjonsIdx]
    valgtIdx := ChromeRotasjonsIdx
    ChromeRotasjonsIdx := (ChromeRotasjonsIdx >= ChromeRotasjonsMaks or ChromeRotasjonsIdx >= chromeVinduer.Length) ? 1 : ChromeRotasjonsIdx + 1

    ; --- Aktiver valgt vindu, åpne ny fane, lim inn lenken, gå dit ---
    try {
        WinActivate("ahk_id " målHwnd)
        WinWaitActive("ahk_id " målHwnd, , 2)
        Send("^t")
        Sleep(150)
        A_Clipboard := lenke
        Send("^v")
        Sleep(80)
        Send("{Enter}")
        ToolTip("🌐 Sendt til Chrome-vindu " valgtIdx "/" ChromeRotasjonsMaks ": " SubStr(lenke, 1, 50))
        SetTimer(() => ToolTip(), -2000)
    } catch as e {
        ToolTip("⚠️ Kunne ikke sende til Chrome: " e.Message)
        SetTimer(() => ToolTip(), -2500)
    }
}

; ==============================================================================
; SEKSJON 4: BANNLISTE (F6) + VALGT TEKST → CHROME MED DYNAMISK ROTASJON (Alt+P)
; ------------------------------------------------------------------------------
; Alt+P fungerer akkurat som Ctrl+Alt+G over: marker lenketeksten (dra over
; den), trykk Alt+P. Forskjellen: den roterer blant SÅ MANGE Chrome-vinduer
; som faktisk er åpne akkurat nå (2, 3, 5, 6 ... uansett antall — ikke tvunget
; til nøyaktig 4), og sjekker den markerte lenken mot bannlisten under. Matcher
; den et sperret domene, blir den IGNORERT og ALDRI sendt til Chrome.
;
; F6 åpner en meny der du kan se, legge til og fjerne domener i bannlisten.
; ==============================================================================
global BannetUrls := [
    "leagueoflegends.com"
]
global AltPRotasjonsIdx := 1
global urlGui := ""

ErUrlBannetF6(url) {
    global BannetUrls
    for domene in BannetUrls {
        if InStr(url, domene)
            return domene
    }
    return ""
}

; Denne hurtigtasten registreres nå dynamisk fra Main.ahk via HK_ChromePaste,
; slik at den kan omprogrammeres i F1-panelet i stedet for å være hardkodet her.

SendValgtTekstAltP() {
    global AltPRotasjonsIdx

    ; --- Slipp Alt (og evt. andre) FØR vi sender Ctrl+C. Dette er selve
    ; grunnen til at kun første lenke fungerte tidligere: Alt+P bruker Alt som
    ; modifikator, og hvis Windows fortsatt ser Alt som nedtrykt når
    ; funksjonen starter, blir Send("^c") i praksis til Ctrl+Alt+C — som ikke
    ; kopierer noe i Chrome. ---
    Send("{Alt up}{Ctrl up}{Shift up}")
    Sleep(30)

    ; --- Kopier det som er markert akkurat nå ---
    gammelPortefølje := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(1) {
        ToolTip("⚠️ Ingen tekst markert! Merk lenken(e) og prøv igjen.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    markertTekst := A_Clipboard
    A_Clipboard := gammelPortefølje

    ; --- FLERE LENKER PÅ ÉN GANG: marker en hel blokk (én lenke per linje,
    ; adskilt med mellomrom/tab, ELLER limt sammen i markdown-format som
    ; [https://a.com](http://b.com) osv.) og alle gyldige lenker i blokken
    ; blir sendt til hvert sitt Chrome-vindu i rotasjon, i én og samme
    ; Alt+P-trykk.
    ;
    ; VIKTIG: Vi finner lenkene med et regex-søk gjennom HELE teksten i
    ; stedet for å bare dele opp på mellomrom/linjeskift. Grunnen: hvis
    ; kilden er markdown-lenker (f.eks. kopiert fra en renderet lenke), kan
    ; to URL-er stå limt sammen med bare [ ] ( ) rundt og imellom seg og
    ; ingen mellomrom — da vil en ren mellomrom-splitting se dette som ÉN
    ; lang "lenke" og enten forkaste den eller bare bruke den første URL-en.
    ; Regexet under plukker ut HVER enkelt gyldig URL for seg, uansett hva
    ; som omgir den (klammer, parenteser, anførselstegn, komma osv.). ---
    kandidater := []
    posisjon := 1
    while (posisjon := RegExMatch(markertTekst, "i)(https?://[^\s\[\]\(\)<>]+|www\.[^\s\[\]\(\)<>]+)", &treff, posisjon)) {
        kandidater.Push(treff[1])
        posisjon += StrLen(treff[1])
    }

    gyldigeLenker := []
    ugyldigeAntall := 0
    sperretAntall := 0
    for token in kandidater {
        url := RTrim(token, ".,;:!?")
        if (RegExMatch(url, "^www\."))
            url := "https://" url
        if (!RegExMatch(url, "^[a-zA-Z][a-zA-Z0-9+.\-]*://")) {
            ugyldigeAntall += 1
            continue
        }
        if (bannetDomene := ErUrlBannetF6(url)) {
            sperretAntall += 1
            continue
        }
        gyldigeLenker.Push(url)
    }

    if (gyldigeLenker.Length = 0) {
        ToolTip("⚠️ Fant ingen gyldige, ikke-sperrede lenker i det markerte." (sperretAntall > 0 ? " (" sperretAntall " sperret)" : ""))
        SetTimer(() => ToolTip(), -2500)
        return
    }

    ; --- Bruk ALLE Chrome-vinduer som faktisk er åpne akkurat nå ---
    chromeVinduer := SorterVindusListeStabiltF11(WinGetList("ahk_exe chrome.exe"))
    if (chromeVinduer.Length = 0) {
        try Run('"' A_ProgramFiles '\Google\Chrome\Application\chrome.exe" --new-window')
        Sleep(900)
        chromeVinduer := SorterVindusListeStabiltF11(WinGetList("ahk_exe chrome.exe"))
        if (chromeVinduer.Length = 0) {
            ToolTip("⚠️ Fant ingen Chrome-vinduer og kunne ikke åpne et nytt. Sjekk installasjonen.")
            SetTimer(() => ToolTip(), -2500)
            return
        }
    }

    ; --- Send hver gyldige lenke til et Chrome-vindu:
    ; FØRSTE runde (så mange lenker som det er vinduer) fordeles i fast
    ; rekkefølge, én per vindu, slik at alle vinduer garantert får noe.
    ; Er det FLERE lenker enn vinduer, blir resten fordelt TILFELDIG blant
    ; vinduene i stedet for å bare fortsette i samme faste rekkefølge. ---
    sendtAntall := 0
    feilAntall := 0
    antallVinduer := chromeVinduer.Length
    rundeTeller := 0
    for url in gyldigeLenker {
        rundeTeller += 1
        if (rundeTeller <= antallVinduer) {
            if (AltPRotasjonsIdx > antallVinduer)
                AltPRotasjonsIdx := 1
            valgtIdx := AltPRotasjonsIdx
            AltPRotasjonsIdx := (AltPRotasjonsIdx >= antallVinduer) ? 1 : AltPRotasjonsIdx + 1
        } else {
            valgtIdx := Random(1, antallVinduer)
        }
        målHwnd := chromeVinduer[valgtIdx]

        try {
            WinActivate("ahk_id " målHwnd)
            WinWaitActive("ahk_id " målHwnd, , 2)
            Send("^t")
            Sleep(150)
            A_Clipboard := url
            Send("^v")
            Sleep(80)
            Send("{Enter}")
            Sleep(120)
            sendtAntall += 1
        } catch {
            feilAntall += 1
        }
    }

    melding := "🌐 Sendt " sendtAntall "/" gyldigeLenker.Length " lenke(r) til " chromeVinduer.Length " Chrome-vindu(er)."
    if (sperretAntall > 0)
        melding .= " 🚫 " sperretAntall " sperret."
    if (ugyldigeAntall > 0)
        melding .= " ⚠️ " ugyldigeAntall " ugyldig(e) ignorert."
    if (feilAntall > 0)
        melding .= " ❌ " feilAntall " feilet."
    ToolTip(melding)
    SetTimer(() => ToolTip(), -3000)
}

TriggerF6UrlListeMeny(*) {
    global urlGui, BannetUrls
    try if IsObject(urlGui) and WinExist("ahk_id " urlGui.Hwnd) {
        urlGui.Destroy()
        urlGui := ""
        return
    }

    SoundPlay("*64")
    urlGui := Gui("-Caption -Border +AlwaysOnTop +0x02000000")
    urlGui.BackColor := "1A1A1A"
    urlGui.MarginX := 25, urlGui.MarginY := 25

    urlGui.SetFont("s11 cWhite Bold", "Segoe UI")
    urlGui.Add("Text", "w320 h25 +0x200", "🚫 BANNLISTE (Alt+P ignorerer disse):")

    urlGui.SetFont("s8.5 cAAAAAA Norm", "Segoe UI")
    urlGui.Add("Text", "w320 xm y+5", "Lenker som inneholder noe av dette blir ALDRI sendt til Chrome.")

    urlGui.SetFont("s9 cWhite Bold")
    lb := urlGui.Add("ListBox", "w320 r6 xm y+15 +Background333333 cWhite", BannetUrls)

    urlGui.Add("Text", "w320 xm y+10", "Nytt domene/URL å sperre:")
    iNy := urlGui.Add("Edit", "w320 xm y+3 r1 +Background333333 cWhite")

    urlGui.Add("Button", "w155 h30 xm y+8 -Theme +Background155724 cWhite", "➕ Legg Til").OnEvent("Click", (btn, *) => LeggTilBannetUrlF6(lb, iNy))
    urlGui.Add("Button", "w155 h30 x+10 yp -Theme +Background721C24 cWhite", "🗑️ Fjern Valgt").OnEvent("Click", (btn, *) => FjernBannetUrlF6(lb))

    urlGui.SetFont("s8 c888888 Norm")
    urlGui.Add("Text", "w320 xm y+12", "------------------------------------------------------------------")

    urlGui.SetFont("s9 cWhite Bold")
    urlGui.Add("Button", "w320 h30 xm y+10 -Theme +Background3A3A3A", "🔄 Reset Standard").OnEvent("Click", (btn, *) => ResetBannlisteF6(lb))
    urlGui.Add("Button", "w320 h32 xm y+10 -Theme +Background222222", "✖ Lukk Meny").OnEvent("Click", (*) => LukkF6UrlListeMeny())

    OnMessage(0x0201, HåndterVinduKlikkF6)
    urlGui.Show("W370")
}

LeggTilBannetUrlF6(lb, iNy) {
    global BannetUrls
    nytt := Trim(iNy.Value)
    if (nytt = "") {
        ToolTip("⚠️ Skriv inn et domene eller en URL først.")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    BannetUrls.Push(nytt)
    lb.Add([nytt])
    iNy.Value := ""
    SoundPlay("*64")
    ToolTip("✅ Lagt til i bannlisten: " nytt)
    SetTimer(() => ToolTip(), -1500)
}

FjernBannetUrlF6(lb) {
    global BannetUrls
    valgtIdx := lb.Value
    if (!valgtIdx) {
        ToolTip("⚠️ Velg et element i listen først.")
        SetTimer(() => ToolTip(), -1500)
        return
    }
    fjernet := BannetUrls[valgtIdx]
    BannetUrls.RemoveAt(valgtIdx)
    lb.Delete(valgtIdx)
    SoundPlay("*48")
    ToolTip("🗑️ Fjernet fra bannlisten: " fjernet)
    SetTimer(() => ToolTip(), -1500)
}

ResetBannlisteF6(lb) {
    global BannetUrls
    BannetUrls := ["leagueoflegends.com"]
    lb.Delete()
    lb.Add(BannetUrls)
    SoundPlay("*64")
    ToolTip("🔄 Bannliste tilbakestilt til standard!")
    SetTimer(() => ToolTip(), -2000)
}

LukkF6UrlListeMeny(*) {
    global urlGui
    try {
        if IsObject(urlGui) {
            urlGui.Destroy()
            urlGui := ""
        }
    } catch {
        global urlGui := ""
    }
}

HåndterVinduKlikkF6(wParam, lParam, msg, hwnd) {
    global urlGui
    try {
        if (IsObject(urlGui) and hwnd = urlGui.Hwnd) {
            PostMessage(0x00A1, 2, 0, , "ahk_id " urlGui.Hwnd)
        }
    }
}
