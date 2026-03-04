#!/usr/bin/env bash
# Watches /home/pi/data/logs/ble-serial.log and:
# - Starts printing when a line contains BOTH [AUTOCONNECT] and Adafruit
# - Prints everything during that block
# - After at least 10 lines have been printed (including the trigger line),
#   the next line that contains [AUTOCONNECT] will end the block (stop after printing it)
# - While *not* printing, shows a spinner on the "next output line" (overwritten in place)
#
# Notes:
# - Designed for mawk; we use -W interactive and fflush().
# - Spinner uses carriage return + ANSI clear-line; if your terminal doesn't support ANSI,
#   you can remove "\033[K" (you'll just overwrite without explicit clearing).

logfile="/home/pi/data/logs/ble-serial.log"

tail -f -n 500 "$logfile" | mawk -W interactive '
BEGIN {
    IGNORECASE = 1
    printing = 0
    lines_since_start = 0

    # Spinner state
    spinner_chars = "/-\\|"
    spinner_idx = 0
    spinner_active = 0
    spinner_prefix = "[waiting] "
}

# --- Utility functions ---
function spinner_tick(    ch) {
    ch = substr(spinner_chars, spinner_idx + 1, 1)
    # \r returns to start of the same line; \033[K clears the line to end (ANSI)
    printf "\r\033[K%s%s", spinner_prefix, ch
    fflush()
    spinner_idx = (spinner_idx + 1) % length(spinner_chars)
    spinner_active = 1
}

function spinner_clear() {
    if (spinner_active) {
        # Clear the spinner line and move to column 0
        printf "\r\033[K"
        fflush()
        spinner_active = 0
    }
}

# --- Trigger: start printing when BOTH tokens appear on the same line ---
/\[AUTOCONNECT\]/ && /Adafruit/ {
    spinner_clear()
    printing = 1
    lines_since_start = 0
    print
    fflush()
    next
}

# --- Printing block: print everything ---
printing {
    lines_since_start++
    # Ensure any spinner is cleared before we output real text
    spinner_clear()
    print
    fflush()

    # After at least 10 printed lines, the next [AUTOCONNECT] ends the block
    if (lines_since_start >= 10 && $0 ~ /\[AUTOCONNECT\]/) {
        printing = 0
        lines_since_start = 0
    }
    next
}

# --- Not printing: show spinner on its own line, overwritten in place ---
{
    spinner_tick()
    next
}
'