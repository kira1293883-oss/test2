#Requires AutoHotkey v2.0

; ==============================================================================
; SEKSJON A: HELE DET DIGITALE FARGEBIBLIOTEKET (THEMES)
; ==============================================================================
global Themes := [
    {n: "1. Beisvart Natt", bg: "1A1A1A", fg: "FFFFFF", ft: "2A2A2A", s: "*64"},
    {n: "2. Cyber Punk",    bg: "2B2B2B", fg: "FFDD00", ft: "444444", s: "*70"},
    {n: "3. Neon Rosa",     bg: "1F111F", fg: "FF00FF", ft: "3A223A", sound: "*80"},
    {n: "4. Matrix Grønn",  bg: "0A140A", fg: "00FF00", ft: "142814", s: "*90"},
    {n: "5. Matrix Matrix", bg: "3A3A3A", fg: "00FFFF", ft: "555555", s: "*60"},
    {n: "6. Klassisk Grå",  bg: "5A5A5A", fg: "FFFFFF", ft: "777777", sound: "*55"},
    {n: "7. Lava Rød",      bg: "2A0A0A", fg: "FF3333", ft: "4A1414", s: "*65"},
    {n: "8. Orange Glød",   bg: "2A1A0A", fg: "FF9900", ft: "4A2A14", s: "*75"},
    {n: "9. Dyp Blå",       bg: "0A142A", fg: "3399FF", ft: "14244A", sound: "*85"},
    {n: "10. Total Mørke",  bg: "000000", fg: "D7D7D7", ft: "222222", s: "*50"}
]

; ==============================================================================
; SEKSJON B: DE TRE FASTE SYSTEMMAPRENE
; ==============================================================================
global SrcM := "R:\all files Wind Roar"
global SucM := "R:\successfully saved"
global FailM := "R:\(\not\) successful saved"

; ==============================================================================
; SEKSJON C: UTPAKKINGSMOTOR (7-Zip) + FLYTTEVERKTØY (TeraCopy)
; ==============================================================================
; 7-Zip tar passordet stille via kommandolinjen (-p"passord") — ingen GUI-dialog
; som kan stoppe automatiseringen halvveis, i motsetning til WinRAR som noen
; ganger popper sitt eget passord-vindu midt i utpakkingen.
global SevenZipSti := A_ProgramFiles "\7-Zip\7z.exe"

; TeraCopy brukes til å FLYTTE de utpakkede filene til Success/Fail-mappene
; etterpå (i stedet for bare å lage en snarveis-lenke). Krever at TeraCopy er
; installert. Sett TeraCopyBrukAktiv := false for å gå tilbake til gammel
; oppførsel (kun snarvei, ingen faktisk flytting).
global TeraCopySti := A_ProgramFiles "\TeraCopy\TeraCopy.exe"
global TeraCopyBrukAktiv := false

; ==============================================================================
; SEKSJON D: EGEN MAPPE FOR PASSORD-FILER (ÉN .TXT PER UTPAKKET FIL)
; ==============================================================================
; I tillegg til den sentrale loggen (Lagrede_Passord.txt på skrivebordet)
; lagres nå ÉN separat .txt-fil per vellykket utpakket fil, med kun det
; passordet som hørte til akkurat den filen. Filnavnet blir det samme som
; det opprinnelige arkivnavnet (f.eks. "MinFil.txt").
global PassordFilMappe := "R:\Lagret Passord"
