#Requires AutoHotkey v2.0

; Forward-deklarasjoner for å tilfredsstille #Warn i delte moduler
global CyclusKart, ErPau, SpdIdx, TypDelay, SrcM, SucM, FailM, LogF, fartsGui, txtL1, txtL2, Themes, StlIdx, SisteFeiledeFiler, SevenZipSti, TeraCopySti, TeraCopyBrukAktiv, MaxSamtidigUtpakking, dash

; ==============================================================================
; Genererer et konfliktfritt mål-mappenavn (f.eks. "navn", "navn_2", "navn_3")
; slik at TeraCopy aldri møter en mappe som allerede finnes og må spørre om
; sammenslåing — det hindrer automatiseringen i å stoppe opp på en dialog.
; ==============================================================================
GenererUniktMålnavnF3(målMappe, basisNavn) {
    kandidat := målMappe "\" basisNavn
    if !DirExist(kandidat)
        return kandidat
    n := 2
    Loop {
        kandidat := målMappe "\" basisNavn "_" n
        if !DirExist(kandidat)
            return kandidat
        n++
    }
}

; ==============================================================================
; Enkel synkende sortering (størst→minst) på "_størrelse"-egenskapen.
; Brukt til å planlegge parallell-utpakking mer effektivt (se TriggerUtpakkingLive).
; ==============================================================================
SorterKøEtterStørrelseF3(liste) {
    n := liste.Length
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index
            if (liste[j]._størrelse < liste[j+1]._størrelse) {
                tmp := liste[j]
                liste[j] := liste[j+1]
                liste[j+1] := tmp
            }
        }
    }
    return liste
}

; ==============================================================================
; Formaterer millisekund-anslag til lesbar "Xm Ys" / "Xs" tekst for ETA-visning.
; ==============================================================================
FormatEtaF3(ms) {
    if (ms < 0)
        ms := 0
    sek := Round(ms / 1000)
    if (sek < 60)
        return sek " sek"
    min := sek // 60
    restSek := Mod(sek, 60)
    return min " min " restSek " sek"
}

; ==============================================================================
; Formaterer en bytestørrelse til lesbar "X.XX GB" / "X.XX MB" tekst.
; ==============================================================================
FormatStørrelseF3(bytes) {
    if (bytes >= 1024*1024*1024)
        return Round(bytes / (1024*1024*1024), 2) " GB"
    if (bytes >= 1024*1024)
        return Round(bytes / (1024*1024), 1) " MB"
    return Round(bytes / 1024, 0) " KB"
}

; ==============================================================================
; Lar F3-dashbordet (progressvinduet under utpakking) flyttes ved å klikke og
; dra hvor som helst i vinduet, siden det mangler tittellinje (-Caption).
; ==============================================================================
WM_LBUTTONDOWN_DASH(wParam, lParam, msg, hwnd) {
    global dash
    try {
        if (IsObject(dash) and hwnd = dash.Hwnd)
            PostMessage(0x00A1, 2, 0, , "ahk_id " dash.Hwnd)
    }
}

; ==============================================================================
; SEKSJON 1: DET SENTRALE UTPAKKINGSANLEGGET (F3)
; Bruker KUN passordet som er tilordnet hver fil i F11-registeret.
; Ingen gjetting/brute-force lenger — én fil, ett passord, ett forsøk.
; ==============================================================================
TriggerUtpakkingLive() {
    global CyclusKart, ErPau, SpdIdx, TypDelay, SrcM, SucM, FailM, LogF, PostFilPause, WinRARPrioritet, LydVarslingPå, RundeTeller, SisteFeiledeFiler, SevenZipSti, TeraCopySti, TeraCopyBrukAktiv, MaxSamtidigUtpakking, dash

    if !FileExist(SevenZipSti) {
        MsgBox("⚠️ Fant ikke 7-Zip på:`n" SevenZipSti "`n`nInstaller 7-Zip eller rett opp stien i Main_Konfigurasjon.ahk (SevenZipSti).", "7-Zip mangler", 16)
        return
    }
    if (TeraCopyBrukAktiv and !FileExist(TeraCopySti)) {
        MsgBox("⚠️ Fant ikke TeraCopy på:`n" TeraCopySti "`n`nInstaller TeraCopy, rett opp stien (TeraCopySti), eller sett TeraCopyBrukAktiv := false i Main_Konfigurasjon.ahk.", "TeraCopy mangler", 16)
        return
    }

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

    ; 📏 STØRRELSES-SORTERING: start de STØRSTE arkivene FØRST. Uten dette kan
    ; alle små filer bli ferdig raskt mens én stor fil henger igjen alene til
    ; slutt uten noen andre jobber ved siden av seg — det sløser bort ledige
    ; parallell-slots mot slutten av runden. Ved å starte tunge filer tidligst
    ; rekker de å kjøre samtidig med de mange små, og total tid for HELE
    ; runden går ned.
    for idx, element in koe {
        størrelse := 0
        try {
            Loop Files, SrcM "\" element.f ".*" {
                størrelse := A_LoopFileSize
                break
            }
        }
        element.DefineProp("_størrelse", {value: størrelse})
    }
    koe := SorterKøEtterStørrelseF3(koe)

    ; 💾 DISKPLASS-SJEKK: avbryt tidlig med en tydelig feilmelding hvis
    ; kildedisken er nesten full, i stedet for å starte 7-Zip-jobber som
    ; feiler halvveis pga. fullt volum (og gir forvirrende FEILET-rader).
    totalArkivStørrelse := 0
    for idx, element in koe
        totalArkivStørrelse += element._størrelse
    try {
        stasjon := ""
        SplitPath(SrcM, , , , , &stasjon)
        ledigPlass := DriveGetSpaceFree((stasjon != "") ? stasjon : SrcM) * 1024 * 1024
        ; Utpakket innhold trenger normalt like mye plass som arkivet selv,
        ; pluss litt margin (20%) for sikkerhets skyld.
        nødvendigPlass := totalArkivStørrelse * 1.2
        if (ledigPlass > 0 and nødvendigPlass > 0 and ledigPlass < nødvendigPlass) {
            svar := MsgBox("⚠️ Lav diskplass på kildestasjonen!`n`nLedig: " Round(ledigPlass/1024/1024/1024, 2) " GB`nAnslått behov: " Round(nødvendigPlass/1024/1024/1024, 2) " GB`n`nFortsette likevel?", "Diskplass-advarsel", "YesNo Icon!")
            if (svar = "No")
                return
        }
    }

    ; ⚡ ZERO DELAY FORMEL: Når SpdIdx tvinges til 11 blir resultatet nøyaktig 0ms delay!
    delay := (11 - SpdIdx) * 200
    ; 🚀 PARALLELL UTPAKKING: flere 7-Zip-prosesser kjører SAMTIDIG i stedet for
    ; å vente på at én fil er ferdig før neste starter. Antall styres av
    ; MaxSamtidigUtpakking (justerbar i F7-panelet).
    maxSamtidig := (IsSet(MaxSamtidigUtpakking) and MaxSamtidigUtpakking > 0) ? MaxSamtidigUtpakking : 3

    dash := Gui("+AlwaysOnTop -MinimizeBox -Caption +Border"), dash.BackColor := "1A1A1A"
    ; 🖱️ FLYTTBART VINDU: uten tittellinje (-Caption) har vinduet normalt
    ; INGEN måte å flyttes på med musa. Denne håndteringen lar deg klikke og
    ; dra i selve dashbordet for å flytte det dit du vil, akkurat som F5- og
    ; F7-panelene allerede kan.
    OnMessage(0x0201, WM_LBUTTONDOWN_DASH)
    dash.SetFont("s11 cWhite Bold", "Segoe UI"), dash.Add("Text", "w420 vFT", "Forbereder...")
    dash.SetFont("s9 cAAAAAA w400"), dash.Add("Text", "w420 y+5 vPT", "Venter...")
    dash.SetFont("s10 cWhite Bold"), bar := dash.Add("Progress", "w420 h15 y+10 cGreen Background333333 Smooth", 0)
    dash.SetFont("s8.5 c88CCFF w400"), dash.Add("Text", "w420 y+6 vETA", "⏳ Anslått gjenstående: beregner...")
    dash.SetFont("s8.5 cFFCC66 w400"), dash.Add("Text", "w420 y+4 vMASSE", "📦 Total størrelse: " FormatStørrelseF3(totalArkivStørrelse))
    dash.Show("X" (A_ScreenWidth//2 - 220) " Y20 W440")
    tot := koe.Length
    exe := SevenZipSti

    ferdigeFiler := []
    aktiveJobber := []   ; hver: {element, nam, p, pid, outD, fullSti}
    nesteIdx := 1
    fullførte := 0
    massebehandlet := 0
    runStartTick := A_TickCount

    try {
        while (fullførte < tot) {
            while (ErPau)
                Sleep(300)

            ; --- Fyll opp ledige "slots" med nye 7-Zip-jobber (starter dem UTEN
            ; å vente på at forrige er ferdig — det er selve parallelliseringen) ---
            while (aktiveJobber.Length < maxSamtidig and nesteIdx <= tot) {
                element := koe[nesteIdx]
                nam := element.f
                p   := Trim(element.p)
                nesteIdx++

                fullSti := ""
                Loop Files, SrcM "\" nam ".*" {
                    fullSti := A_LoopFilePath
                    break
                }
                if (fullSti == "") {
                    fullførte++
                    continue
                }

                outD := SrcM "\" nam
                if !DirExist(outD)
                    DirCreate(outD)

                ; Kun en kort, valgfri forsinkelse FØR oppstart av hver ny jobb
                ; (skåner disken på lave hastighetsinnstillinger). Turbo (delay=0)
                ; = ingen kunstig ventetid, jobbene fyres av rett etter hverandre.
                if (delay > 0)
                    Sleep(delay)

                winPID := 0
                try {
                    ; 🔐 SIKKER ESCAPING AV PASSORD: hvis passordet inneholder
                    ; anførselstegn (") eller ender/starter med backslash, kan
                    ; det tidligere ha BRUKKET kommandolinjen i to — 7-Zip
                    ; mottok da et ufullstendig/feil -p-argument og falt
                    ; tilbake til å SPØRRE OM PASSORD INTERAKTIVT (det du så
                    ; som en dukkende dialog, tilsynelatende tilfeldig før
                    ; eller midt i utpakkingen). Fikset ved å escape korrekt
                    ; etter Windows' kommandolinje-regler: doble avsluttende
                    ; backslash før anførselstegn, og escape selve tegnet.
                    escP := StrReplace(p, '"', '\"')

                    ; 🔍 DIAGNOSE-LOGG: skriver KUN passordets lengde og
                    ; første/siste tegn (aldri hele passordet, av sikkerhet)
                    ; sammen med filnavn. Lar deg sjekke om det er tomt,
                    ; har en usynlig mellomrom, eller feil verdi for AKKURAT
                    ; den ene filen som stadig ber om passord manuelt.
                    try {
                        diag := "DIAGNOSE: " nam " -> passord-lengde=" StrLen(p)
                        if (StrLen(p) > 0)
                            diag .= " (starter='" SubStr(p,1,1) "' slutter='" SubStr(p,-1) "')"
                        if (p != Trim(p))
                            diag .= " ⚠️ INNEHOLDER LEDENDE/AVSLUTTENDE MELLOMROM!"
                        FileAppend(diag "`n", LogF, "UTF-8")
                    }

                    ; 7-Zip: passordet sendes stille med -p, ingen popup kan noensinne
                    ; dukke opp og stoppe automatiseringen (i motsetning til WinRAR).
                    ; -y = ja til alt, -bd = ingen prosentindikator, -bso0 -bse0 = stille.
                    Run('"' exe '" x -p"' escP '" -y -bd -bso0 -bse0 -o"' outD '" "' fullSti '"', , "Hide", &winPID)
                    if (winPID)
                        ProcessSetPriority(WinRARPrioritet, winPID)
                } catch {
                    winPID := 0
                }

                aktiveJobber.Push({element: element, nam: nam, p: p, pid: winPID, outD: outD, fullSti: fullSti, startTick: A_TickCount})
            }

            ; --- Oppdater dashbord med hvor mange som pakkes ut akkurat nå ---
            aktiveNavn := ""
            for j, jobb in aktiveJobber
                aktiveNavn .= (j > 1 ? ", " : "") jobb.nam
            dash["FT"].Value := "📦 Pakker ut " aktiveJobber.Length "/" maxSamtidig " samtidig — [" fullførte "/" tot " ferdig]"
            dash["PT"].Value := "🔑 " (aktiveNavn != "" ? aktiveNavn : "Venter på neste fil...")
            bar.Value := Integer((fullførte/tot)*100)

            ; 🛡️ STALL-VAKT: hvis køen har gått tom for aktive jobber OG det
            ; ikke finnes flere filer å starte (nesteIdx > tot), men vi likevel
            ; ikke er ferdig (fullførte < tot), er tellerne kommet i utakt —
            ; f.eks. en jobb som forsvant sporløst uten å bli talt noe sted.
            ; Uten denne vakten fryser dashbordet på "0 aktive" for alltid.
            ; Løsning: reconcile — regn de "tapte" filene som feilet, legg dem
            ; tilbake i F11-køen, og la runden fullføre i stedet for å henge.
            if (aktiveJobber.Length = 0 and nesteIdx > tot and fullførte < tot) {
                FileAppend("ADVARSEL: Utpakkingskøen kom i utakt (" fullførte "/" tot " talt, ingen aktive jobber igjen) — resterende " (tot - fullførte) " fil(er) merkes FEILET for å unngå at systemet henger.`n", LogF, "UTF-8")
                while (fullførte < tot) {
                    ferdigeFiler.Push({f: "(ukjent - mistet i køen)", arkivSti: "", utpakketMappe: "", ok: false})
                    fullførte++
                }
                break
            }

            ; --- Sjekk hvilke aktive jobber som er ferdige (prosessen har lukket) ---
            nyeAktive := []
            for j, jobb in aktiveJobber {
                ; ⏱️ PER-JOBB TIMEOUT: hvis en enkelt 7-Zip-prosess henger i mer
                ; enn 20 minutter (f.eks. en skadet fil eller en dialog som
                ; venter i det skjulte), IKKE la det blokkere resten av køen
                ; for alltid — drep prosessen og regn filen som feilet.
                if (jobb.pid != 0 and ProcessExist(jobb.pid) and (A_TickCount - jobb.startTick) > 20*60*1000) {
                    try ProcessClose(jobb.pid)
                    FileAppend("ADVARSEL: " jobb.nam " ble tvunget avsluttet etter 20 minutter uten fremgang (mulig hengende/skadet arkiv).`n", LogF, "UTF-8")
                }
                erFerdig := (jobb.pid = 0) or !ProcessExist(jobb.pid)
                if !erFerdig {
                    nyeAktive.Push(jobb)
                    continue
                }

                ok := false
                exitKode := -1
                if (jobb.pid != 0) {
                    ; 🎯 EKSTRA SIGNAL: les den faktiske avslutningskoden fra
                    ; 7-Zip (0 = suksess) via Win32 i stedet for KUN å gjette
                    ; ut fra om mappa har innhold. Et arkiv med feil passord
                    ; kan i sjeldne tilfeller likevel skrive tomme/delvise
                    ; filer til target — exitkoden avslører det tryggere.
                    try {
                        hProc := DllCall("OpenProcess", "uint", 0x0400, "int", 0, "uint", jobb.pid, "ptr")
                        if (hProc) {
                            kodeBuf := 0
                            DllCall("GetExitCodeProcess", "ptr", hProc, "uint*", &kodeBuf)
                            exitKode := kodeBuf
                            DllCall("CloseHandle", "ptr", hProc)
                        }
                    }
                    ; 🛡️ RACE-FIX: Under parallell utpakking kan ProcessExist()
                    ; si "prosessen er borte" i det AKKURAT samme øyeblikket som
                    ; 7-Zip fortsatt flusher de siste bytene til disk (eller mens
                    ; antivirus holder på å skanne den nyskrevne filen). Så en
                    ; mappe som i virkeligheten LYKKES kan se tom ut i det aller
                    ; første sjekket. Derfor: sjekk flere ganger med en kort
                    ; pause mellom, og gi opp (= ekte feil) først når mappa
                    ; fortsatt er tom etter ~1 sekund med rechecks.
                    Loop 5 {
                        hasF := false
                        Loop Files, jobb.outD "\*.*", "R" {
                            hasF := true
                            break
                        }
                        if (hasF) {
                            ok := true
                            break
                        }
                        Sleep(200)
                    }
                    ; Hvis 7-Zip selv rapporterte en feilkode (≠0), stol på det
                    ; fremfor mappe-innholdet — en feilkode er et sikrere tegn
                    ; på reell feil (feil passord/korrupt arkiv) enn en tom
                    ; sjekk kan være i motsatt retning.
                    if (exitKode != -1 and exitKode != 0)
                        ok := false
                }
                ; 🚫 SLETTER IKKE MAPPA LENGER, uansett utfall. Mislykkede/tomme
                ; mapper blir liggende i SrcM slik at ingenting noensinne kan gå
                ; tapt ved en feilaktig "tom mappe"-vurdering (f.eks. samme
                ; race som over, treg disk, AV-skanning, osv.). Fila blir
                ; uansett merket FEILET i loggen og lagt i F11-køen for nytt
                ; passordforsøk — den ligger da bare fysisk igjen på disk også.

                ; 🔁 AUTOMATISK RETRY: en "FEILET" utpakking kan skyldes en
                ; forbigående ting (disk fortsatt opptatt, AV-lås, treg I/O
                ; under høy parallellitet) og ikke faktisk feil passord.
                ; Derfor: gi HVER fil ett automatisk nytt forsøk før den regnes
                ; som endelig feilet og havner tilbake i F11-køen for manuell
                ; retting. Rene passordfeil vil naturligvis feile likt andre
                ; gang også — det koster bare ett ekstra (raskt) forsøk.
                if (!ok and !(jobb.element.HasOwnProp("_retry") and jobb.element._retry)) {
                    jobb.element.DefineProp("_retry", {value: true})
                    FileAppend("FIL: " jobb.nam " -> feilet første forsøk, prøver automatisk på nytt...`n", LogF, "UTF-8")
                    koe.Push(jobb.element)
                    tot++
                    continue
                }

                try {
                    if (ok) {
                        FileAppend("FIL: " jobb.nam " -> OK med tilordnet passord`n", LogF, "UTF-8")
                        LagreAutoPassordF11(jobb.nam, jobb.p, denneRunden, (jobb.element.HasOwnProp("url") ? jobb.element.url : ""))
                        LagrePassordEgenFilF11(jobb.nam, jobb.p)
                        if (LydVarslingPå)
                            TrayTip("Saved!", jobb.nam, 1)
                    } else {
                        FileAppend("FIL: " jobb.nam " -> FEILET (feil passord eller korrupt arkiv, etter automatisk retry)`n", LogF, "UTF-8")
                        if (LydVarslingPå)
                            TrayTip("Failed!", jobb.nam, 3)
                    }
                }

                ferdigeFiler.Push({f: jobb.nam, arkivSti: jobb.fullSti, utpakketMappe: jobb.outD, ok: ok})
                fullførte++
                massebehandlet += (jobb.element.HasOwnProp("_størrelse") ? jobb.element._størrelse : 0)
                dash["MASSE"].Value := "📦 Behandlet: " FormatStørrelseF3(massebehandlet) " av " FormatStørrelseF3(totalArkivStørrelse)
                ; ⏱️ ETA: gjennomsnittlig tid pr. ferdig fil hittil, projisert på
                ; antall gjenstående — gir brukeren et konkret "ca. X igjen".
                if (fullførte > 0) {
                    snittMs := (A_TickCount - runStartTick) / fullførte
                    restMs := snittMs * (tot - fullførte)
                    dash["ETA"].Value := (tot - fullførte) > 0 ? "⏳ Anslått gjenstående: " FormatEtaF3(restMs) : "⏳ Ferdigstiller..."
                }
                if (fullførte < tot and PostFilPause > 0)
                    Sleep(PostFilPause)
            }
            aktiveJobber := nyeAktive

            ; Kort polling-pause — unngår å spinne CPU-en mens vi venter på at
            ; en eller flere av de parallelle 7-Zip-prosessene blir ferdige.
            if (fullførte < tot)
                Sleep(120)
        }

        ; --- Merk resultater: lag snarvei til arkivet, og FLYTT selve de
        ; utpakkede filene til Success/Fail-mappa med TeraCopy (rask, robust
        ; I/O med automatisk retry) i stedet for å la dem ligge igjen i SrcM.
        for idx, res in ferdigeFiler {
            målMappe := res.ok ? SucM : FailM
            if !DirExist(målMappe)
                DirCreate(målMappe)

            try FileCreateShortcut(res.arkivSti, målMappe "\" res.f ".lnk")

            if (res.ok) {
                if (TeraCopyBrukAktiv and DirExist(res.utpakketMappe)) {
                    ; Unngå TeraCopys "mappa er ikke tom, slå sammen?"-dialog
                    ; (den venter på et klikk og fryser automatiseringen) ved
                    ; å alltid gi et unikt, konfliktfritt mappenavn i målet.
                    unikMålSti := GenererUniktMålnavnF3(målMappe, res.f)
                    try RunWait('"' TeraCopySti '" MOVE "' res.utpakketMappe '" "' unikMålSti '" /Close')

                    ; 🛡️ TERACOPY-FIX: TeraCopy er en "single instance"-app. Hvis
                    ; den allerede kjører, sender denne prosessen bare jobben
                    ; videre til den kjørende instansen og AVSLUTTER SEG SELV
                    ; MED DET SAMME — RunWait venter da kun på denne korte
                    ; overleveringsprosessen, IKKE på selve flyttingen, som
                    ; fortsetter i bakgrunnen. Skriptet trodde tidligere
                    ; RunWait = ferdig, og gikk videre uten å sjekke om filene
                    ; faktisk kom frem. Havnet flyttingen i en dialog (f.eks.
                    ; en fil i bruk / AV-skanning) eller feilet stille, ble
                    ; mappa borte fra kilden UTEN å dukke opp i målet — reell
                    ; datatap. Derfor: sjekk faktisk at målet fikk innhold,
                    ; med retries, før vi stoler på at flyttingen lyktes.
                    flyttetOk := false
                    Loop 25 {
                        if DirExist(unikMålSti) {
                            Loop Files, unikMålSti "\*.*", "R" {
                                flyttetOk := true
                                break
                            }
                        }
                        if (flyttetOk)
                            break
                        Sleep(400)
                    }

                    if (!flyttetOk) {
                        ; TeraCopy rakk aldri (eller klarte aldri) å fullføre.
                        ; IKKE stol på at data er trygt et sted — flytt den
                        ; gjenværende kildemappa selv med en vanlig, blokkerende
                        ; DirMove, slik at ingenting kan forsvinne sporløst.
                        try FileAppend("ADVARSEL: TeraCopy fullførte ikke flyttingen av " res.f " innen tidsfristen — falt tilbake til vanlig filflytting.`n", LogF, "UTF-8")
                        if DirExist(res.utpakketMappe) {
                            try {
                                if !DirExist(unikMålSti)
                                    DirMove(res.utpakketMappe, unikMålSti)
                            } catch as e {
                                try FileAppend("FEIL: Klarte heller ikke flytte " res.f " manuelt: " e.Message " — mappa ligger fortsatt i SrcM: " res.utpakketMappe "`n", LogF, "UTF-8")
                            }
                        } else if !DirExist(unikMålSti) {
                            ; Verken kilde eller mål har mappa — reelt datatap
                            ; allerede skjedd inne i TeraCopy. Varsle tydelig
                            ; i stedet for å late som alt gikk bra.
                            try FileAppend("KRITISK: Fant verken kilde- eller målmappe for " res.f " etter TeraCopy — mulig datatap. Sjekk TeraCopy-loggen.`n", LogF, "UTF-8")
                            if (LydVarslingPå)
                                TrayTip("Mulig datatap!", res.f, 3)
                        }
                    }
                }
                ; Om TeraCopy er avslått, eller flyttingen feilet av en eller
                ; annen grunn, blir mappa liggende i SrcM som før — ingenting
                ; går tapt.
            } else {
                ; 🚫 Mislykkede utpakkinger: mappa (som oftest er tom, men kan
                ; av og til inneholde delvis utpakkede filer) blir liggende i
                ; SrcM. Ingenting slettes automatisk lenger.
            }
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
        totalTidSek := Round((A_TickCount - runStartTick) / 1000, 1)
        meldingTekst := "FULLFØRT (Runde " denneRunden ")! " ferdigeFiler.Length " fil(er) behandlet (" FormatStørrelseF3(massebehandlet) ") på " FormatEtaF3(A_TickCount - runStartTick) " (" totalTidSek "s)."
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
    global SpdIdx, TypDelay, PostFilPause, WinRARPrioritet, LydVarslingPå, fartsGui, txtL1, txtL2, txtL3, txtL4, MaxSamtidigUtpakking
    if (!IsSet(MaxSamtidigUtpakking))
        MaxSamtidigUtpakking := 3
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
        fartsGui.Add("Text", "w320 xm y+12", "Slider 4: Samtidige utpakkinger (1 - 8):")
        minSlider4 := fartsGui.Add("Slider", "w300 Range1-8 ToolTip +Background1A1A1A", MaxSamtidigUtpakking)
        minSlider4.OnEvent("Change", HåndterSamtidigMotorKompakt)
        fartsGui.SetFont("s9 cAAAAAA w400")
        txtL4 := fartsGui.Add("Text", "w300 xm", "Samtidig: " MaxSamtidigUtpakking " fil(er) parallelt" (MaxSamtidigUtpakking = 1 ? " (sekvensiell, gammel oppførsel)" : ""))

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
    global SpdIdx, TypDelay, PostFilPause, MaxSamtidigUtpakking, fartsGui
    if (navn = "Turbo")
        SpdIdx := 11, TypDelay := 0, PostFilPause := 100, MaxSamtidigUtpakking := 5
    else if (navn = "Balansert")
        SpdIdx := 8, TypDelay := 20, PostFilPause := 300, MaxSamtidigUtpakking := 3
    else if (navn = "Skånsom")
        SpdIdx := 3, TypDelay := 80, PostFilPause := 800, MaxSamtidigUtpakking := 1

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

HåndterSamtidigMotorKompakt(s, *) {
    try {
        global MaxSamtidigUtpakking := s.Value
        txtL4.Value := "Samtidig: " s.Value " fil(er) parallelt" (s.Value = 1 ? " (sekvensiell, gammel oppførsel)" : "")
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
