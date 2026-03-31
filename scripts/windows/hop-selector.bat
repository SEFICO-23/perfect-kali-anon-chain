@echo off
REM ══════════════════════════════════════════════════════════════════════
REM  Mullvad Multihop Relay Selector — Windows Launcher
REM  Launches the interactive selector inside Kali WSL2
REM ══════════════════════════════════════════════════════════════════════
REM
REM  Usage:
REM    hop-selector           (interactive menu)
REM    hop-selector --status  (show current config)
REM    hop-selector rs pt     (quick apply: Serbia entry → Portugal exit)
REM

if "%1"=="" (
    wsl -d kali-linux -u root -- /usr/local/bin/mullvad-hop-selector.sh
) else if "%1"=="--status" (
    wsl -d kali-linux -u root -- /usr/local/bin/mullvad-hop-selector.sh --status
) else if "%1"=="--presets" (
    wsl -d kali-linux -u root -- /usr/local/bin/mullvad-hop-selector.sh --presets
) else (
    wsl -d kali-linux -u root -- /usr/local/bin/mullvad-hop-selector.sh --apply %1 %2
)
