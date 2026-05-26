#!/data/data/com.termux/files/usr/bin/bash

#=============================================================
#
#   ⚡ TITANIUM BACKUP — Termux Backup & Restore Manager
#   Author: iaemon
#   GitHub: https://github.com/iaemonbd/TITANIUM-BACKUP
#   License: MIT
#
#   One intelligent script to backup & restore your entire
#   Termux environment. Full, selective, auto-restore,
#   smart cleanup — everything in one place.
#
#=============================================================

set -euo pipefail

#-----------------------------------------------------------
# Colors & Styles
#-----------------------------------------------------------
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
P='\033[0;35m'
B='\033[1;34m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

#-----------------------------------------------------------
# Configuration
#-----------------------------------------------------------
BACKUP_DIR="/sdcard/termux-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LATEST_FULL="${BACKUP_DIR}/LATEST_FULL.tar.gz"
LATEST_SELECTIVE="${BACKUP_DIR}/LATEST_SELECTIVE.tar.gz"
SCRIPT_NAME="titanium-backup.sh"
VERSION="2.0.0"

#-----------------------------------------------------------
# Utility Functions
#-----------------------------------------------------------

check_storage() {
    if [ ! -d "/sdcard" ] || [ ! -w "/sdcard" ]; then
        echo -e "${R}❌ Error: /sdcard access denied!${NC}"
        echo -e "${Y}👉 Run: termux-setup-storage${NC}"
        exit 1
    fi
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        echo -e "${R}❌ Error: Cannot create backup directory!${NC}"
        exit 1
    fi
}

header() {
    clear 2>/dev/null || true
    echo -e "${C}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC}                                                            ${C}║${NC}"
    echo -e "${C}║${NC}  ${BOLD}${P}         ⚡ TITANIUM BACKUP & RESTORE MANAGER${NC}            ${C}║${NC}"
    echo -e "${C}║${NC}       ${DIM}v${VERSION}  ·  One Script, Total Control${NC}                ${C}║${NC}"
    echo -e "${C}║${NC}                                                            ${C}║${NC}"
    echo -e "${C}║${NC}       ${Y}Storage: ${BACKUP_DIR}${NC}                                ${C}║${NC}"
    echo -e "${C}║${NC}                                                            ${C}║${NC}"
    echo -e "${C}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_menu() {
    echo -e "  ${G}[1]${NC} ${BOLD}🗄️   Full Backup${NC}        — Complete Termux environment"
    echo -e "  ${G}[2]${NC} ${BOLD}📦   Selective Backup${NC}   — Packages + Configs + Scripts"
    echo -e "  ${G}[3]${NC} ${BOLD}♻️   Full Restore${NC}       — From Latest or Choose"
    echo -e "  ${G}[4]${NC} ${BOLD}🔧   Selective Restore${NC}  — Packages & Configs only"
    echo -e "  ${G}[5]${NC} ${BOLD}📋   List Backups${NC}       — View all with size & date"
    echo -e "  ${G}[6]${NC} ${BOLD}🗑️   Delete Old${NC}         — Keep last 3, remove rest"
    echo -e "  ${G}[7]${NC} ${BOLD}⚡   Quick Backup${NC}       — Silent mode for cron jobs"
    echo -e "  ${R}[0]${NC} ${BOLD}❌   Exit${NC}"
    echo ""
    echo -ne "  ${Y}👉 Select option [0-7]: ${NC}"
}

spinner() {
    local pid=$1
    local msg="$2"
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 7); do
            printf "\r  ${Y}%s %s${NC}" "${spin:$i:1}" "$msg"
            sleep 0.1
        done
    done
    wait "$pid"
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        printf "\r  ${G}✅ %s${NC}\n" "$msg"
    else
        printf "\r  ${R}❌ %s (failed)${NC}\n" "$msg"
    fi
    return $exit_code
}

confirm_danger() {
    echo -e "\n  ${R}⚠️  WARNING: This will overwrite current Termux data!${NC}"
    echo -e "  ${Y}💡 Tip: Clear Termux data first (Settings → Apps → Termux → Clear Data)${NC}"
    echo ""
    read -p "  Type 'yes' to proceed: " confirm
    [[ "$confirm" == "yes" ]]
}

#-----------------------------------------------------------
# 1. FULL BACKUP
#-----------------------------------------------------------
do_full_backup() {
    header
    echo -e "  ${C}🗄️  FULL BACKUP MODE${NC}\n"

    local filename="termux-full-${TIMESTAMP}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"

    echo -e "  ${Y}📂 Destination:${NC} ${filepath}"
    echo -e "  ${Y}⏳ Starting backup...${NC}\n"

    (
        cd /data/data/com.termux/files
        tar -czpf "$filepath" \
            --exclude='./home/storage' \
            --exclude='./home/.cache' \
            --exclude='./usr/var/cache/apt/archives' \
            --exclude='./usr/tmp' \
            ./home ./usr
    ) &

    if spinner $! "Creating full backup"; then
        if [ -f "$filepath" ]; then
            ln -sf "$filepath" "$LATEST_FULL"
            local size=$(du -h "$filepath" | cut -f1)
            echo -e "\n  ${G}✅ Full Backup Successful!${NC}"
            echo -e "  ${G}📁 File:${NC}    ${filename}"
            echo -e "  ${G}📊 Size:${NC}    ${size}"
            echo -e "  ${G}🔗 Latest:${NC}   LATEST_FULL.tar.gz → ${filename}"
        else
            echo -e "\n  ${R}❌ Backup file not created!${NC}"
        fi
    else
        echo -e "\n  ${R}❌ Backup failed!${NC}"
        rm -f "$filepath" 2>/dev/null || true
    fi

    read -p $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 2. SELECTIVE BACKUP
#-----------------------------------------------------------
do_selective_backup() {
    header
    echo -e "  ${C}📦 SELECTIVE BACKUP MODE${NC}\n"

    local folder="selective-${TIMESTAMP}"
    local workdir="${BACKUP_DIR}/${folder}"
    mkdir -p "$workdir"

    # Package list
    echo -e "  ${Y}📋 Generating package list...${NC}"
    pkg list-installed 2>/dev/null | cut -d/ -f1 > "${workdir}/packages-list.txt"
    local pkg_count=$(wc -l < "${workdir}/packages-list.txt" | tr -d ' ')
    echo -e "  ${G}   ✓ ${pkg_count} packages listed${NC}"

    # Home configs
    echo -e "  ${Y}📂 Backing up configs & scripts...${NC}"
    (
        cd "$HOME"
        tar -czf "${workdir}/home-configs.tar.gz" \
            .bashrc .zshrc .profile .termux .config .ssh \
            bin scripts .local 2>/dev/null || true
    ) &
    spinner $! "Archiving home directory"

    # Info file
    cat > "${workdir}/backup-info.txt" <<EOF
TITANIUM BACKUP — Selective Archive
Created: $(date)
Packages: ${pkg_count}
Hostname: $(hostname)
EOF

    # Final archive
    local final="${BACKUP_DIR}/termux-selective-${TIMESTAMP}.tar.gz"
    (
        cd "$BACKUP_DIR"
        tar -czf "$final" "$(basename "$workdir")"
        rm -rf "$workdir"
    ) &
    spinner $! "Finalizing archive"

    if [ -f "$final" ]; then
        ln -sf "$final" "$LATEST_SELECTIVE"
        local size=$(du -h "$final" | cut -f1)
        echo -e "\n  ${G}✅ Selective Backup Successful!${NC}"
        echo -e "  ${G}📁 File:${NC}    $(basename "$final")"
        echo -e "  ${G}📊 Size:${NC}    ${size}"
        echo -e "  ${G}📦 Packages:${NC} ${pkg_count}"
    else
        echo -e "\n  ${R}❌ Selective backup failed!${NC}"
    fi

    read -p $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 3. FULL RESTORE
#-----------------------------------------------------------
do_full_restore() {
    header
    echo -e "  ${C}♻️  FULL RESTORE MODE${NC}\n"

    # Find available backups
    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null || true)

    if [ ${#backups[@]} -eq 0 ] || [ -z "${backups[0]}" ]; then
        echo -e "  ${R}❌ No full backups found!${NC}"
        read -p $'\n  🔙 Press Enter to return...'
        return
    fi

    echo -e "  ${Y}📂 Available Full Backups:${NC}\n"
    local i=1
    for b in "${backups[@]}"; do
        local size=$(du -h "$b" | cut -f1)
        local name=$(basename "$b")
        echo -e "  ${G}[$i]${NC} ${name} ${Y}(${size})${NC}"
        ((i++))
    done

    # Show latest link target
    if [ -L "$LATEST_FULL" ]; then
        local latest_target=$(readlink "$LATEST_FULL" 2>/dev/null || echo "none")
        if [ -f "$latest_target" ]; then
            echo -e "\n  ${G}[L]${NC} Latest → ${Y}$(basename "$latest_target")${NC}"
        fi
    fi

    echo -e "  ${R}[0]${NC} Cancel"
    echo ""
    read -p "  👉 Select backup [1-$((i-1))/L/0]: " choice

    local target=""
    if [[ "$choice" == "0" ]]; then return
    elif [[ "$choice" =~ ^[Ll]$ ]]; then target="$LATEST_FULL"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        target="${backups[$((choice-1))]}"
    else
        echo -e "\n  ${R}❌ Invalid option!${NC}"
        sleep 1; return
    fi

    if [ ! -f "$target" ]; then
        echo -e "\n  ${R}❌ Backup file not found!${NC}"
        sleep 1; return
    fi

    echo -e "\n  ${Y}📂 Selected:${NC} $(basename "$(readlink -f "$target")")"

    if ! confirm_danger; then
        echo -e "\n  ${Y}❌ Cancelled${NC}"
        sleep 1; return
    fi

    echo -e "\n  ${Y}⏳ Restoring...${NC}"
    echo -e "  ${R}🛑 Do NOT close this window!${NC}\n"

    (
        cd /data/data/com.termux/files
        # Safety: rename old instead of delete
        mv home "home.old.${TIMESTAMP}" 2>/dev/null || true
        mv usr "usr.old.${TIMESTAMP}" 2>/dev/null || true

        # Extract
        tar -xzpf "$target"

        # Cleanup old backups on success
        rm -rf "home.old.${TIMESTAMP}" "usr.old.${TIMESTAMP}" 2>/dev/null || true
    ) &

    if spinner $! "Restoring full backup"; then
        echo -e "\n  ${G}✅ Restore Successful!${NC}"
        echo -e "  ${G}🎉 Termux is back to exactly how it was!${NC}"
        echo -e "\n  ${R}⚠️  IMPORTANT:${NC}"
        echo -e "  ${Y}   Close Termux completely and reopen it.${NC}"
        echo -e "  ${Y}   Do NOT run any commands before restarting.${NC}"
    else
        echo -e "\n  ${R}❌ Restore failed!${NC}"
        echo -e "  ${Y}💡 Check if /sdcard has enough free space.${NC}"
    fi

    read -p $'\n  🔙 Press Enter to return (but restart Termux first)...'
}

#-----------------------------------------------------------
# 4. SELECTIVE RESTORE
#-----------------------------------------------------------
do_selective_restore() {
    header
    echo -e "  ${C}🔧 SELECTIVE RESTORE MODE${NC}\n"

    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null || true)

    if [ ${#backups[@]} -eq 0 ] || [ -z "${backups[0]}" ]; then
        echo -e "  ${R}❌ No selective backups found!${NC}"
        read -p $'\n  🔙 Press Enter to return...'
        return
    fi

    echo -e "  ${Y}📂 Available Selective Backups:${NC}\n"
    local i=1
    for b in "${backups[@]}"; do
        local size=$(du -h "$b" | cut -f1)
        echo -e "  ${G}[$i]${NC} $(basename "$b") ${Y}(${size})${NC}"
        ((i++))
    done

    if [ -L "$LATEST_SELECTIVE" ]; then
        local lt=$(readlink "$LATEST_SELECTIVE" 2>/dev/null || echo "")
        [ -f "$lt" ] && echo -e "\n  ${G}[L]${NC} Latest → ${Y}$(basename "$lt")${NC}"
    fi

    echo -e "  ${R}[0]${NC} Cancel"
    echo ""
    read -p "  👉 Select backup [1-$((i-1))/L/0]: " choice

    local target=""
    if [[ "$choice" == "0" ]]; then return
    elif [[ "$choice" =~ ^[Ll]$ ]]; then target="$LATEST_SELECTIVE"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        target="${backups[$((choice-1))]}"
    else
        echo -e "\n  ${R}❌ Invalid option!${NC}"
        sleep 1; return
    fi

    if [ ! -f "$target" ]; then
        echo -e "\n  ${R}❌ File not found!${NC}"
        sleep 1; return
    fi

    echo -e "\n  ${Y}⏳ Starting selective restore...${NC}"

    # Extract to temp
    local tmpdir="${BACKUP_DIR}/.restore-tmp-${TIMESTAMP}"
    mkdir -p "$tmpdir"

    (
        cd "$tmpdir"
        tar -xzf "$target"
    ) &
    spinner $! "Extracting archive"

    # Find inner folder
    local inner=$(find "$tmpdir" -maxdepth 1 -type d | grep -v "^${tmpdir}$" | head -1)

    if [ -z "$inner" ] || [ ! -d "$inner" ]; then
        echo -e "\n  ${R}❌ Invalid backup structure!${NC}"
        rm -rf "$tmpdir"
        sleep 1; return
    fi

    # Restore packages
    if [ -f "${inner}/packages-list.txt" ]; then
        local pkg_count=$(wc -l < "${inner}/packages-list.txt" | tr -d ' ')
        echo -e "\n  ${Y}📦 ${pkg_count} packages to install...${NC}"
        echo -e "  ${DIM}(This may take several minutes)${NC}\n"

        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            printf "  ${C}  → %-30s${NC}" "$pkg"
            if pkg install -y "$pkg" >/dev/null 2>&1; then
                echo -e "${G} ✓${NC}"
            else
                echo -e "${R} ✗${NC}"
            fi
        done < "${inner}/packages-list.txt"
    fi

    # Restore configs
    if [ -f "${inner}/home-configs.tar.gz" ]; then
        echo -e "\n  ${Y}📂 Restoring home configs...${NC}"
        (
            cd "$HOME"
            tar -xzf "${inner}/home-configs.tar.gz" 2>/dev/null || true
        ) &
        spinner $! "Applying configs"
    fi

    # Cleanup
    rm -rf "$tmpdir"

    echo -e "\n  ${G}✅ Selective Restore Complete!${NC}"
    echo -e "  ${G}🔧 Packages & configs are back to their previous state.${NC}"

    read -p $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 5. LIST BACKUPS
#-----------------------------------------------------------
list_backups() {
    header
    echo -e "  ${C}📋 BACKUP INVENTORY${NC}\n"
    echo -e "  ${BOLD}${P}📂 Location:${NC} ${BACKUP_DIR}\n"

    # Full backups
    echo -e "  ${Y}🗄️  Full Backups:${NC}"
    local full_count=0
    for f in "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null; do
        [ -f "$f" ] || continue
        local size=$(du -h "$f" | cut -f1)
        local date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        local name=$(basename "$f")
        local marker=""
        [ "$f" == "$(readlink -f "$LATEST_FULL" 2>/dev/null)" ] && marker=" ${G}← LATEST${NC}"
        echo -e "  ${G}  •${NC} ${name} ${Y}[${size}]${NC} ${C}${date}${NC}${marker}"
        ((full_count++))
    done
    [ "$full_count" -eq 0 ] && echo -e "  ${R}  (none)${NC}"

    echo ""

    # Selective backups
    echo -e "  ${Y}📦 Selective Backups:${NC}"
    local sel_count=0
    for f in "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null; do
        [ -f "$f" ] || continue
        local size=$(du -h "$f" | cut -f1)
        local date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        local name=$(basename "$f")
        local marker=""
        [ "$f" == "$(readlink -f "$LATEST_SELECTIVE" 2>/dev/null)" ] && marker=" ${G}← LATEST${NC}"
        echo -e "  ${G}  •${NC} ${name} ${Y}[${size}]${NC} ${C}${date}${NC}${marker}"
        ((sel_count++))
    done
    [ "$sel_count" -eq 0 ] && echo -e "  ${R}  (none)${NC}"

    echo ""
    echo -e "  ${BOLD}Total:${NC} ${G}${full_count}${NC} Full + ${G}${sel_count}${NC} Selective"

    local total=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo -e "  ${BOLD}Disk Used:${NC} ${Y}${total}${NC}"

    read -p $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 6. DELETE OLD BACKUPS
#-----------------------------------------------------------
delete_old() {
    header
    echo -e "  ${C}🗑️  DELETE OLD BACKUPS${NC}\n"

    echo -e "  ${Y}Choose cleanup mode:${NC}\n"
    echo -e "  ${G}[1]${NC} Full Backups only     — Keep last 3"
    echo -e "  ${G}[2]${NC} Selective Backups     — Keep last 3"
    echo -e "  ${G}[3]${NC} Both types            — Keep last 3 each"
    echo -e "  ${R}[4]${NC} ${R}DELETE ALL${NC}            — ${R}⚠️  Everything!${NC}"
    echo -e "  ${Y}[0]${NC} Cancel"
    echo ""
    read -p "  👉 Option: " del_choice

    case "$del_choice" in
        1)
            echo ""
            ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f"
                echo -e "  ${R}🗑️  Deleted:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ Old full backups cleaned up${NC}"
            ;;
        2)
            echo ""
            ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f"
                echo -e "  ${R}🗑️  Deleted:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ Old selective backups cleaned up${NC}"
            ;;
        3)
            echo ""
            ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f"; echo -e "  ${R}🗑️  Full:${NC} $(basename "$f")"
            done
            ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f"; echo -e "  ${R}🗑️  Selective:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ All old backups cleaned up${NC}"
            ;;
        4)
            echo ""
            read -p "  ${R}Type 'DELETE' to remove ALL backups: ${NC}" confirm
            if [ "$confirm" == "DELETE" ]; then
                rm -f "${BACKUP_DIR}"/termux-*.tar.gz
                rm -f "${BACKUP_DIR}"/LATEST_*.tar.gz
                echo -e "\n  ${G}✅ All backups deleted${NC}"
            else
                echo -e "\n  ${Y}❌ Cancelled${NC}"
            fi
            ;;
        *)
            echo -e "\n  ${Y}❌ Cancelled${NC}"
            ;;
    esac

    read -p $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 7. QUICK BACKUP (Silent Mode)
#-----------------------------------------------------------
quick_backup() {
    header
    echo -e "  ${C}⚡ QUICK SILENT BACKUP${NC}\n"

    local filename="termux-full-${TIMESTAMP}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"

    echo -e "  ${Y}⏳ Running silent backup...${NC}"
    echo -e "  ${DIM}No prompts, no spinners — just pure speed.${NC}\n"

    cd /data/data/com.termux/files
    if tar -czpf "$filepath" \
        --exclude='./home/storage' \
        --exclude='./home/.cache' \
        --exclude='./usr/var/cache/apt/archives' \
        --exclude='./usr/tmp' \
        ./home ./usr; then

        ln -sf "$filepath" "$LATEST_FULL"
        local size=$(du -h "$filepath" | cut -f1)
        echo -e "  ${G}✅ Quick Backup Done!${NC}"
        echo -e "  ${G}📊 Size:${NC} ${size}"
        echo -e "  ${G}📁 File:${NC} ${filename}"
    else
        echo -e "  ${R}❌ Quick backup failed!${NC}"
        rm -f "$filepath" 2>/dev/null || true
    fi

    sleep 2
}

#-----------------------------------------------------------
# MAIN LOOP
#-----------------------------------------------------------

main() {
    check_storage

    # If argument "7" is passed (for cron), run quick backup directly
    if [ $# -ge 1 ] && [ "$1" == "7" ]; then
        quick_backup
        exit 0
    fi

    while true; do
        header
        show_menu
        read -r choice
        echo ""

        case "$choice" in
            1) do_full_backup ;;
            2) do_selective_backup ;;
            3) do_full_restore ;;
            4) do_selective_restore ;;
            5) list_backups ;;
            6) delete_old ;;
            7) quick_backup ;;
            0)
                header
                echo -e "\n  ${G}👋 Thanks for using TITANIUM BACKUP!${NC}"
                echo -e "  ${DIM}github.com/iaemonbd/TITANIUM-BACKUP${NC}\n"
                exit 0
                ;;
            *)
                echo -e "  ${R}❌ Invalid option! Please enter 0-7${NC}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
