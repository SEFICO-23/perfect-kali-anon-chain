#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# mullvad-hop-selector.sh — Interactive Mullvad Multihop Relay Selector
# ══════════════════════════════════════════════════════════════════════════════
#
# Provides a visual, color-coded dropdown menu for selecting Mullvad entry
# and exit relays with OPSEC intelligence (Five Eyes, Nine Eyes, 14-Eyes,
# EU data retention, and safe relay classifications).
#
# Usage:
#   sudo ./mullvad-hop-selector.sh              # Interactive mode
#   sudo ./mullvad-hop-selector.sh --status      # Show current config
#   sudo ./mullvad-hop-selector.sh --presets     # Show preset combinations
#   sudo ./mullvad-hop-selector.sh --apply rs pt # Quick apply entry=rs exit=pt
#
# Part of: kali-anon-chain
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_BLUE='\033[44m'
BG_YELLOW='\033[43m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
UNDERLINE='\033[4m'

# ── OPSEC Classifications ───────────────────────────────────────────────────
# Each country is classified by intelligence-sharing alliance membership
# and data retention risk. This drives the color coding in the menu.

declare -A COUNTRY_NAMES=(
    [al]="Albania"     [ar]="Argentina"   [au]="Australia"   [at]="Austria"
    [be]="Belgium"     [br]="Brazil"      [bg]="Bulgaria"    [ca]="Canada"
    [cl]="Chile"       [co]="Colombia"    [hr]="Croatia"     [cy]="Cyprus"
    [cz]="Czech Rep."  [dk]="Denmark"     [ee]="Estonia"     [fi]="Finland"
    [fr]="France"      [de]="Germany"     [gr]="Greece"      [hk]="Hong Kong"
    [hu]="Hungary"     [id]="Indonesia"   [ie]="Ireland"     [il]="Israel"
    [it]="Italy"       [jp]="Japan"       [my]="Malaysia"    [mx]="Mexico"
    [nl]="Netherlands" [nz]="New Zealand" [ng]="Nigeria"     [no]="Norway"
    [pe]="Peru"        [ph]="Philippines" [pl]="Poland"      [pt]="Portugal"
    [ro]="Romania"     [rs]="Serbia"      [sg]="Singapore"   [sk]="Slovakia"
    [si]="Slovenia"    [za]="South Africa" [es]="Spain"      [se]="Sweden"
    [ch]="Switzerland" [th]="Thailand"    [tr]="Turkey"      [gb]="UK"
    [ua]="Ukraine"     [us]="USA"
)

# Five Eyes — highest surveillance risk
FIVE_EYES="au ca gb nz us"

# Nine Eyes — Five Eyes + 4
NINE_EYES="dk fr nl no"

# Fourteen Eyes — Nine Eyes + 5
FOURTEEN_EYES="be de it se es"

# EU members (data retention directives apply)
EU_MEMBERS="at be bg hr cy cz dk ee fi fr de gr hu ie it nl pl pt ro sk si es se"

# SAFE countries — outside all alliances, no EU data retention
# These are the BEST choices for entry relays
SAFE_COUNTRIES="al ar br cl co hk id jp my mx ng pe ph rs sg za th tr ua ch"

get_opsec_class() {
    local code="$1"
    if echo "$FIVE_EYES" | grep -qw "$code"; then
        echo "5EYES"
    elif echo "$NINE_EYES" | grep -qw "$code"; then
        echo "9EYES"
    elif echo "$FOURTEEN_EYES" | grep -qw "$code"; then
        echo "14EYES"
    elif echo "$EU_MEMBERS" | grep -qw "$code"; then
        echo "EU"
    else
        echo "SAFE"
    fi
}

get_opsec_color() {
    case "$1" in
        5EYES)  echo "$RED" ;;
        9EYES)  echo "$YELLOW" ;;
        14EYES) echo "$YELLOW" ;;
        EU)     echo "$BLUE" ;;
        SAFE)   echo "$GREEN" ;;
        *)      echo "$WHITE" ;;
    esac
}

get_opsec_label() {
    case "$1" in
        5EYES)  echo "${BG_RED}${WHITE} 5-EYES ${RESET}" ;;
        9EYES)  echo "${BG_YELLOW}${WHITE} 9-EYES ${RESET}" ;;
        14EYES) echo "${BG_YELLOW}${WHITE} 14-EYS ${RESET}" ;;
        EU)     echo "${BG_BLUE}${WHITE}   EU   ${RESET}" ;;
        SAFE)   echo "${BG_GREEN}${WHITE}  SAFE  ${RESET}" ;;
    esac
}

# ── Banner ───────────────────────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    cat << 'BANNER'
    ╔══════════════════════════════════════════════════════════════╗
    ║       🛡️  MULLVAD MULTIHOP RELAY SELECTOR  🛡️              ║
    ║       Kali Anon Chain                                      ║
    ╚══════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${RESET}"
    echo -e "  ${DIM}Legend: ${GREEN}■ SAFE${RESET} ${DIM}(no alliance)${RESET}  ${BLUE}■ EU${RESET}  ${YELLOW}■ 9/14-Eyes${RESET}  ${RED}■ 5-Eyes${RESET}"
    echo -e "  ${DIM}Entry relay sees your source IP. Exit relay sees your destination.${RESET}"
    echo -e "  ${DIM}Best practice: SAFE entry + any exit. NEVER use 5-Eyes for entry.${RESET}"
    echo ""
}

# ── Status Display ───────────────────────────────────────────────────────────

show_status() {
    echo -e "${BOLD}${UNDERLINE}Current Mullvad Configuration${RESET}\n"

    local status
    status=$(mullvad status 2>&1)
    local relay_info
    relay_info=$(mullvad relay get 2>&1)

    if echo "$status" | grep -q "Connected"; then
        echo -e "  Status:    ${GREEN}●${RESET} ${BOLD}Connected${RESET}"
    elif echo "$status" | grep -q "Connecting"; then
        echo -e "  Status:    ${YELLOW}●${RESET} ${BOLD}Connecting...${RESET}"
    else
        echo -e "  Status:    ${RED}●${RESET} ${BOLD}Disconnected${RESET}"
    fi

    # Parse current relay
    local current_relay
    current_relay=$(echo "$status" | grep "Relay:" | sed 's/.*Relay:\s*//' || echo "N/A")
    echo -e "  Relay:     ${WHITE}$current_relay${RESET}"

    # Parse features
    local features
    features=$(echo "$status" | grep "Features:" | sed 's/.*Features:\s*//' || echo "N/A")
    echo -e "  Features:  ${CYAN}$features${RESET}"

    # Parse visible location
    local location
    location=$(echo "$status" | grep "Visible location:" | sed 's/.*Visible location:\s*//' || echo "N/A")
    echo -e "  Location:  ${WHITE}$location${RESET}"

    # Parse multihop state
    local multihop
    multihop=$(echo "$relay_info" | grep "Multihop state:" | awk '{print $NF}')
    if [ "$multihop" = "enabled" ]; then
        echo -e "  Multihop:  ${GREEN}✓ Enabled${RESET}"
    else
        echo -e "  Multihop:  ${RED}✗ Disabled${RESET}"
    fi

    # Parse entry location
    local entry_loc
    entry_loc=$(echo "$relay_info" | grep "Multihop entry:" | sed 's/.*Multihop entry:\s*//' || echo "N/A")
    if [ -n "$entry_loc" ] && [ "$entry_loc" != "N/A" ]; then
        echo -e "  Entry:     ${WHITE}$entry_loc${RESET}"
    fi

    # Parse exit location
    local exit_loc
    exit_loc=$(echo "$relay_info" | grep "Location:" | head -1 | sed 's/.*Location:\s*//' || echo "N/A")
    echo -e "  Exit:      ${WHITE}$exit_loc${RESET}"

    echo ""
}

# ── Country Selector ─────────────────────────────────────────────────────────

# Build sorted country list grouped by OPSEC classification
build_country_menu() {
    local purpose="$1"  # "entry" or "exit"
    local i=1

    echo -e "\n${BOLD}${UNDERLINE}Select $purpose relay:${RESET}\n"

    if [ "$purpose" = "entry" ]; then
        echo -e "  ${DIM}⚠  Entry relay sees your SOURCE IP. Choose a SAFE country.${RESET}\n"
    else
        echo -e "  ${DIM}ℹ  Exit relay determines your visible location to the target.${RESET}\n"
    fi

    # Group 1: SAFE countries (recommended for entry)
    echo -e "  ${GREEN}${BOLD}── SAFE (No Alliance, No EU) ──${RESET}"
    local safe_list=()
    for code in $(echo "$SAFE_COUNTRIES" | tr ' ' '\n' | sort); do
        if [ -n "${COUNTRY_NAMES[$code]:-}" ]; then
            printf "  ${GREEN}%3d)${RESET} %-2s  %-16s $(get_opsec_label SAFE)\n" "$i" "$code" "${COUNTRY_NAMES[$code]}"
            safe_list+=("$code")
            ((i++))
        fi
    done

    # Group 2: EU countries
    echo -e "\n  ${BLUE}${BOLD}── EU (Data Retention Risk) ──${RESET}"
    local eu_only=""
    for code in $(echo "$EU_MEMBERS" | tr ' ' '\n' | sort); do
        # Skip if already in 9/14-Eyes
        if echo "$NINE_EYES $FOURTEEN_EYES" | grep -qw "$code"; then continue; fi
        if [ -n "${COUNTRY_NAMES[$code]:-}" ]; then
            printf "  ${BLUE}%3d)${RESET} %-2s  %-16s $(get_opsec_label EU)\n" "$i" "$code" "${COUNTRY_NAMES[$code]}"
            ((i++))
        fi
    done

    # Group 3: 14-Eyes
    echo -e "\n  ${YELLOW}${BOLD}── 14-Eyes Alliance ──${RESET}"
    for code in $(echo "$FOURTEEN_EYES" | tr ' ' '\n' | sort); do
        if [ -n "${COUNTRY_NAMES[$code]:-}" ]; then
            printf "  ${YELLOW}%3d)${RESET} %-2s  %-16s $(get_opsec_label 14EYES)\n" "$i" "$code" "${COUNTRY_NAMES[$code]}"
            ((i++))
        fi
    done

    # Group 4: 9-Eyes
    echo -e "\n  ${YELLOW}${BOLD}── 9-Eyes Alliance ──${RESET}"
    for code in $(echo "$NINE_EYES" | tr ' ' '\n' | sort); do
        if [ -n "${COUNTRY_NAMES[$code]:-}" ]; then
            printf "  ${YELLOW}%3d)${RESET} %-2s  %-16s $(get_opsec_label 9EYES)\n" "$i" "$code" "${COUNTRY_NAMES[$code]}"
            ((i++))
        fi
    done

    # Group 5: 5-Eyes (WARNING)
    echo -e "\n  ${RED}${BOLD}── 5-Eyes Alliance (HIGH RISK) ──${RESET}"
    for code in $(echo "$FIVE_EYES" | tr ' ' '\n' | sort); do
        if [ -n "${COUNTRY_NAMES[$code]:-}" ]; then
            printf "  ${RED}%3d)${RESET} %-2s  %-16s $(get_opsec_label 5EYES)\n" "$i" "$code" "${COUNTRY_NAMES[$code]}"
            ((i++))
        fi
    done

    echo ""
}

# Build the ordered code array matching the menu numbers
build_code_array() {
    local codes=()
    # SAFE
    for code in $(echo "$SAFE_COUNTRIES" | tr ' ' '\n' | sort); do
        [ -n "${COUNTRY_NAMES[$code]:-}" ] && codes+=("$code")
    done
    # EU (excluding 9/14-eyes)
    for code in $(echo "$EU_MEMBERS" | tr ' ' '\n' | sort); do
        echo "$NINE_EYES $FOURTEEN_EYES" | grep -qw "$code" && continue
        [ -n "${COUNTRY_NAMES[$code]:-}" ] && codes+=("$code")
    done
    # 14-Eyes
    for code in $(echo "$FOURTEEN_EYES" | tr ' ' '\n' | sort); do
        [ -n "${COUNTRY_NAMES[$code]:-}" ] && codes+=("$code")
    done
    # 9-Eyes
    for code in $(echo "$NINE_EYES" | tr ' ' '\n' | sort); do
        [ -n "${COUNTRY_NAMES[$code]:-}" ] && codes+=("$code")
    done
    # 5-Eyes
    for code in $(echo "$FIVE_EYES" | tr ' ' '\n' | sort); do
        [ -n "${COUNTRY_NAMES[$code]:-}" ] && codes+=("$code")
    done
    echo "${codes[@]}"
}

select_country() {
    local purpose="$1"
    local -a codes
    IFS=' ' read -ra codes <<< "$(build_code_array)"

    build_country_menu "$purpose"

    local selection
    while true; do
        echo -ne "  ${BOLD}Enter number or country code (e.g. 'rs' or '17'):${RESET} "
        read -r selection

        # Check if it's a number
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            local idx=$((selection - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#codes[@]}" ]; then
                local chosen="${codes[$idx]}"
                local opsec
                opsec=$(get_opsec_class "$chosen")
                if [ "$purpose" = "entry" ] && [ "$opsec" = "5EYES" ]; then
                    echo -e "\n  ${RED}${BOLD}⚠  WARNING: ${COUNTRY_NAMES[$chosen]} is in 5-Eyes. They can see your SOURCE IP.${RESET}"
                    echo -ne "  ${YELLOW}Are you sure? (y/N):${RESET} "
                    read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                fi
                echo "$chosen"
                return 0
            fi
        fi

        # Check if it's a country code
        if [ -n "${COUNTRY_NAMES[$selection]:-}" ]; then
            local opsec
            opsec=$(get_opsec_class "$selection")
            if [ "$purpose" = "entry" ] && [ "$opsec" = "5EYES" ]; then
                echo -e "\n  ${RED}${BOLD}⚠  WARNING: ${COUNTRY_NAMES[$selection]} is in 5-Eyes. They can see your SOURCE IP.${RESET}"
                echo -ne "  ${YELLOW}Are you sure? (y/N):${RESET} "
                read -r confirm
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
            fi
            echo "$selection"
            return 0
        fi

        echo -e "  ${RED}Invalid selection. Try again.${RESET}"
    done
}

# ── Presets ──────────────────────────────────────────────────────────────────

show_presets() {
    echo -e "\n${BOLD}${UNDERLINE}Recommended Multihop Presets${RESET}\n"
    echo -e "  ${DIM}Each preset maximizes jurisdiction separation between entry and exit.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}1)${RESET} ${BOLD}Balkan Shield${RESET}      Entry: ${GREEN}rs${RESET} (Serbia)      → Exit: ${BLUE}pt${RESET} (Portugal)"
    echo -e "     ${DIM}Default config. Serbia is outside all alliances. Portugal has clean IPs.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}2)${RESET} ${BOLD}Swiss Vault${RESET}        Entry: ${GREEN}ch${RESET} (Switzerland) → Exit: ${BLUE}ro${RESET} (Romania)"
    echo -e "     ${DIM}Swiss privacy laws + Romanian minimal retention. Strong legal separation.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}3)${RESET} ${BOLD}Eastern Wall${RESET}       Entry: ${GREEN}rs${RESET} (Serbia)      → Exit: ${BLUE}bg${RESET} (Bulgaria)"
    echo -e "     ${DIM}Both Balkan. Fast latency. Bulgaria has minimal logging infrastructure.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}4)${RESET} ${BOLD}Asia Ghost${RESET}         Entry: ${GREEN}sg${RESET} (Singapore)   → Exit: ${GREEN}jp${RESET} (Japan)"
    echo -e "     ${DIM}Both outside Western alliances. Best for APAC targets.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}5)${RESET} ${BOLD}Latin Shadow${RESET}       Entry: ${GREEN}br${RESET} (Brazil)      → Exit: ${GREEN}ar${RESET} (Argentina)"
    echo -e "     ${DIM}South American jurisdiction. Good for LATAM targets, far from 5-Eyes.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}6)${RESET} ${BOLD}Ukraine Shield${RESET}     Entry: ${GREEN}ua${RESET} (Ukraine)     → Exit: ${GREEN}rs${RESET} (Serbia)"
    echo -e "     ${DIM}Both outside EU and all alliances. No data retention treaties.${RESET}\n"

    echo -e "  ${GREEN}${BOLD}7)${RESET} ${BOLD}Turkish Cloak${RESET}      Entry: ${GREEN}tr${RESET} (Turkey)      → Exit: ${GREEN}ch${RESET} (Switzerland)"
    echo -e "     ${DIM}Turkey is non-cooperative with Western intel. Swiss exit for clean IPs.${RESET}\n"

    echo -ne "  ${BOLD}Select preset (1-7) or press Enter to go back:${RESET} "
    read -r choice

    case "$choice" in
        1) apply_relay "rs" "pt" ;;
        2) apply_relay "ch" "ro" ;;
        3) apply_relay "rs" "bg" ;;
        4) apply_relay "sg" "jp" ;;
        5) apply_relay "br" "ar" ;;
        6) apply_relay "ua" "rs" ;;
        7) apply_relay "tr" "ch" ;;
        *) return ;;
    esac
}

# ── Apply Relay Configuration ────────────────────────────────────────────────

apply_relay() {
    local entry="$1"
    local exit_relay="$2"

    local entry_name="${COUNTRY_NAMES[$entry]:-$entry}"
    local exit_name="${COUNTRY_NAMES[$exit_relay]:-$exit_relay}"
    local entry_class
    entry_class=$(get_opsec_class "$entry")
    local exit_class
    exit_class=$(get_opsec_class "$exit_relay")

    echo -e "\n${BOLD}Applying multihop configuration:${RESET}"
    echo -e "  Entry: $(get_opsec_color "$entry_class")$entry_name ($entry)${RESET} $(get_opsec_label "$entry_class")"
    echo -e "  Exit:  $(get_opsec_color "$exit_class")$exit_name ($exit_relay)${RESET} $(get_opsec_label "$exit_class")"
    echo ""

    # Apply settings
    echo -ne "  Setting tunnel protocol to WireGuard... "
    mullvad relay set tunnel-protocol wireguard >/dev/null 2>&1
    echo -e "${GREEN}✓${RESET}"

    echo -ne "  Enabling multihop... "
    mullvad relay set multihop on >/dev/null 2>&1
    echo -e "${GREEN}✓${RESET}"

    echo -ne "  Setting entry relay → $entry_name... "
    mullvad relay set entry location "$entry" >/dev/null 2>&1
    echo -e "${GREEN}✓${RESET}"

    echo -ne "  Setting exit relay → $exit_name... "
    mullvad relay set location "$exit_relay" >/dev/null 2>&1
    echo -e "${GREEN}✓${RESET}"

    echo -ne "  Reconnecting... "
    mullvad reconnect >/dev/null 2>&1
    echo -e "${GREEN}✓${RESET}"

    # Wait for connection
    echo -ne "  Waiting for tunnel..."
    for i in $(seq 1 20); do
        sleep 2
        local status
        status=$(mullvad status 2>&1 | head -1)
        if echo "$status" | grep -q "Connected"; then
            echo -e " ${GREEN}✓ Connected!${RESET}"
            echo ""
            show_status
            return 0
        fi
        echo -ne "."
    done

    echo -e " ${RED}✗ Timeout after 40s${RESET}"
    echo -e "  ${YELLOW}Run 'mullvad status' to check manually.${RESET}"
    return 1
}

# ── Main Menu ────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        print_banner
        show_status

        echo -e "  ${BOLD}Actions:${RESET}"
        echo -e "  ${CYAN}1)${RESET} Select entry + exit relays (custom)"
        echo -e "  ${CYAN}2)${RESET} Apply a preset combination"
        echo -e "  ${CYAN}3)${RESET} Change entry relay only"
        echo -e "  ${CYAN}4)${RESET} Change exit relay only"
        echo -e "  ${CYAN}5)${RESET} Toggle multihop on/off"
        echo -e "  ${CYAN}6)${RESET} Reconnect (same config)"
        echo -e "  ${CYAN}7)${RESET} Disconnect VPN"
        echo -e "  ${CYAN}q)${RESET} Quit"
        echo ""
        echo -ne "  ${BOLD}Choice:${RESET} "
        read -r choice

        case "$choice" in
            1)
                clear
                print_banner
                local entry exit_r
                entry=$(select_country "entry")
                clear
                print_banner
                exit_r=$(select_country "exit")
                apply_relay "$entry" "$exit_r"
                echo -e "\n  ${DIM}Press Enter to continue...${RESET}"
                read -r
                ;;
            2)
                clear
                print_banner
                show_presets
                echo -e "\n  ${DIM}Press Enter to continue...${RESET}"
                read -r
                ;;
            3)
                clear
                print_banner
                local entry
                entry=$(select_country "entry")
                local current_exit
                current_exit=$(mullvad relay get 2>&1 | grep "Location:" | head -1 | grep -oP 'country \K\S+')
                apply_relay "$entry" "${current_exit:-pt}"
                echo -e "\n  ${DIM}Press Enter to continue...${RESET}"
                read -r
                ;;
            4)
                clear
                print_banner
                local exit_r
                exit_r=$(select_country "exit")
                local current_entry
                current_entry=$(mullvad relay get 2>&1 | grep "Multihop entry:" | grep -oP ', \K\S+$' || echo "rs")
                apply_relay "${current_entry:-rs}" "$exit_r"
                echo -e "\n  ${DIM}Press Enter to continue...${RESET}"
                read -r
                ;;
            5)
                local mh_state
                mh_state=$(mullvad relay get 2>&1 | grep "Multihop state:" | awk '{print $NF}')
                if [ "$mh_state" = "enabled" ]; then
                    mullvad relay set multihop off
                    echo -e "\n  ${YELLOW}Multihop disabled.${RESET} Single-hop mode active."
                else
                    mullvad relay set multihop on
                    echo -e "\n  ${GREEN}Multihop enabled.${RESET}"
                fi
                mullvad reconnect >/dev/null 2>&1
                sleep 3
                echo -e "  ${DIM}Press Enter to continue...${RESET}"
                read -r
                ;;
            6)
                echo -ne "\n  Reconnecting..."
                mullvad reconnect >/dev/null 2>&1
                sleep 5
                echo -e " ${GREEN}Done.${RESET}"
                sleep 1
                ;;
            7)
                mullvad disconnect >/dev/null 2>&1
                echo -e "\n  ${RED}VPN disconnected.${RESET}"
                sleep 1
                ;;
            q|Q)
                echo -e "\n  ${DIM}Stay safe. 🛡️${RESET}\n"
                exit 0
                ;;
            *)
                echo -e "\n  ${RED}Invalid choice.${RESET}"
                sleep 1
                ;;
        esac
        clear
    done
}

# ── CLI Arguments ────────────────────────────────────────────────────────────

case "${1:-}" in
    --status|-s)
        print_banner
        show_status
        ;;
    --presets|-p)
        print_banner
        show_presets
        ;;
    --apply|-a)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: $0 --apply <entry_code> <exit_code>"
            echo "Example: $0 --apply rs pt"
            exit 1
        fi
        print_banner
        apply_relay "$2" "$3"
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (none)           Interactive menu mode"
        echo "  --status, -s     Show current Mullvad configuration"
        echo "  --presets, -p    Show and apply preset relay combinations"
        echo "  --apply, -a      Quick apply: $0 --apply <entry> <exit>"
        echo "  --help, -h       Show this help"
        echo ""
        echo "Examples:"
        echo "  $0                   # Full interactive mode"
        echo "  $0 --apply rs pt     # Serbia entry → Portugal exit"
        echo "  $0 --apply ch ro     # Switzerland entry → Romania exit"
        echo "  $0 --status          # Show current config"
        ;;
    "")
        clear
        main_menu
        ;;
    *)
        echo "Unknown option: $1"
        echo "Try: $0 --help"
        exit 1
        ;;
esac
