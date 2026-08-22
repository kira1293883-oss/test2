#Requires AutoHotkey v2.0

; ==============================================================================
; SYSTEMDIAGNOSTIKK (brukt av F5-panelet)
; ==============================================================================
RunDiag() {
    global SrcM
    try {
        MsgBox(FileExist(A_ProgramFiles "\WinRAR\WinRAR.exe") ? "✅ WinRAR OK! Mappe: " SrcM : "⚠️ WinRAR Mangler!", "Diagnose", 4096)
    }
}
