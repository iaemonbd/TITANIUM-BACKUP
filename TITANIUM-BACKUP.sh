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
#   smart cleanup, integrity checks — everything in one place.
#
#=============================================================

set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'

#-----------------------------------------------------------
# Colors & Styles
#-----------------------------------------------------------
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
P='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

#-----------------------------------------------------------
# Configuration (defaults, overridable via config file)
#-----------------------------------------------------------
BACKUP_DIR="/sdcard/termux-backups"
KEEP_COUNT=5              # backups to keep per type when auto-pruning
AUTO_PRUNE=true           # prune old backups automatically after each new one
LOW_BATTERY_THRESHOLD=20  # warn below this % if not charging

CONFIG_DIR="$HOME/.config/titanium-backup"
CONFIG_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    cat > "$CONFIG_FILE" <<EOF
# Titanium Backup configuration — edit and re-run the script
BACKUP_DIR="${BACKUP_DIR}"
KEEP_COUNT=${KEEP_COUNT}
AUTO_PRUNE=${AUTO_PRUNE}
LOW_BATTERY_THRESHOLD=${LOW_BATTERY_THRESHOLD}
EOF
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LATEST_FULL="${BACKUP_DIR}/LATEST_FULL.tar.gz"
LATEST_SELECTIVE="${BACKUP_DIR}/LATEST_SELECTIVE.tar.gz"
SCRIPT_NAME="titanium-backup.sh"
VERSION="3.0.0"
LOG_FILE="${BACKUP_DIR}/titanium-backup.log"

#-----------------------------------------------------------
# Utility Functions
#-----------------------------------------------------------

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

pause() {
    # Skip "press enter" prompts when running non-interactively (cron, CI, etc.)
    if [ -t 0 ]; then
        read -r -p "$1"
    fi
}

have_termux_api() {
    command -v termux-notification >/dev/null 2>&1
}

notify() {
    have_termux_api && termux-notification --title "$1" --content "$2" >/dev/null 2>&1 || true
}

wake_lock() {
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true
}

wake_unlock() {
    command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock || true
}

get_compressor() {
    # pigz uses all CPU cores and is drop-in compatible with gzip's format
    if command -v pigz >/dev/null 2>&1; then
        echo "pigz"
    else
        echo "gzip"
    fi
}

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
    if ! command -v pigz >/dev/null 2>&1; then
        log "Tip: install pigz for faster multi-core compression (pkg install pigz)"
    fi
}

check_battery() {
    # Only meaningful with Termux:API installed; otherwise skip silently
    have_termux_api || command -v termux-battery-status >/dev/null 2>&1 || return 0
    command -v termux-battery-status >/dev/null 2>&1 || return 0
    local json pct status
    json=$(termux-battery-status 2>/dev/null) || return 0
    pct=$(echo "$json" | grep -o '"percentage": *[0-9]*' | grep -o '[0-9]*$' || true)
    status=$(echo "$json" | grep -o '"status": *"[A-Z]*"' | grep -o '"[A-Z]*"' | tr -d '"' || true)
    if [ -n "$pct" ] && [ "$pct" -lt "$LOW_BATTERY_THRESHOLD" ] && [ "$status" != "CHARGING" ] && [ "$status" != "FULL" ]; then
        echo -e "  ${R}⚠️  Battery is low (${pct}%) and not charging.${NC}"
        if [ -t 0 ]; then
            read -r -p "  Continue anyway? [y/N]: " ans
            [[ "$ans" =~ ^[Yy]$ ]] || return 1
        else
            log "Aborted: low battery (${pct}%) in non-interactive mode"
            return 1
        fi
    fi
    return 0
}

check_space() {
    # $1 = estimated KB needed
    local needed_kb="$1" avail_kb
    avail_kb=$(df -Pk "$BACKUP_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "${avail_kb:-}" ] && [ "$avail_kb" -lt "$needed_kb" ]; then
        echo -e "  ${R}❌ Not enough free space! Need ~$((needed_kb / 1024))MB, have $((avail_kb / 1024))MB free${NC}"
        return 1
    fi
    return 0
}

write_checksum() {
    local file="$1"
    (cd "$(dirname "$file")" && sha256sum "$(basename "$file")" > "$(basename "$file").sha256") 2>/dev/null || true
}

verify_checksum() {
    local file="$1" sumfile="${1}.sha256"
    [ -f "$sumfile" ] || return 2
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sumfile")" >/dev/null 2>&1)
}

prune_backups() {
    # $1 = glob pattern (relative to BACKUP_DIR), $2 = label for logs
    [ "$AUTO_PRUNE" = "true" ] || return 0
    local pattern="$1" label="$2" files=() f count
    while IFS= read -r f; do files+=("$f"); done < <(ls -1t ${BACKUP_DIR}/${pattern} 2>/dev/null || true)
    count=${#files[@]}
    if [ "$count" -gt "$KEEP_COUNT" ]; then
        for ((idx = KEEP_COUNT; idx < count; idx++)); do
            rm -f "${files[$idx]}" "${files[$idx]}.sha256" 2>/dev/null || true
            log "Auto-pruned old ${label} backup: $(basename "${files[$idx]}")"
        done
        echo -e "  ${DIM}🧹 Auto-pruned $((count - KEEP_COUNT)) old ${label} backup(s), keeping last ${KEEP_COUNT}${NC}"
    fi
}

header() {
    clear 2>/dev/null || true
    echo -e "${C}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC}                                                            ${C}║${NC}"
    echo -e "${C}║${NC}  ${BOLD}${P}         ⚡ TITANIUM BACKUP & RESTORE MANAGER${NC}            ${C}║${NC}"
    echo -e "${C}║${NC}       ${DIM}v${VERSION}  ·  One Script, Total Control${NC}                ${C}║${NC}"
    echo -e "${C}║${NC}                                                            ${C}║${NC}"
    echo -e "${C}║${NC}       ${Y}Storage: ${BACKUP_DIR}${NC}"
    echo -e "${C}║${NC}       ${Y}Compressor: $(get_compressor)  ·  Keep last: ${KEEP_COUNT}${NC}"
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
    echo -e "  ${G}[8]${NC} ${BOLD}🔍   Verify Backups${NC}     — Checksum + archive integrity"
    echo -e "  ${G}[9]${NC} ${BOLD}⚙️   Settings${NC}           — Edit configuration"
    echo -e "  ${R}[0]${NC} ${BOLD}❌   Exit${NC}"
    echo ""
    echo -ne "  ${Y}👉 Select option [0-9]: ${NC}"
}

spinner() {
    local pid=$1 msg="$2"
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
    read -r -p "  Type 'yes' to proceed: " confirm
    [[ "$confirm" == "yes" ]]
}

#-----------------------------------------------------------
# 1. FULL BACKUP
#-----------------------------------------------------------
do_full_backup() {
    header
    echo -e "  ${C}🗄️  FULL BACKUP MODE${NC}\n"
    check_battery || { pause $'\n  🔙 Press Enter to return...'; return; }

    local filename="termux-full-${TIMESTAMP}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"
    local comp; comp=$(get_compressor)

    echo -e "  ${Y}📏 Estimating size...${NC}"
    local est_kb
    est_kb=$(du -sk /data/data/com.termux/files/home /data/data/com.termux/files/usr 2>/dev/null | awk '{sum+=$1} END{print sum}')
    check_space "${est_kb:-0}" || { pause $'\n  🔙 Press Enter to return...'; return; }

    echo -e "  ${Y}📂 Destination:${NC} ${filepath}"
    echo -e "  ${Y}🗜️  Compressor:${NC} ${comp}"
    echo -e "  ${Y}⏳ Starting backup...${NC}\n"

    trap wake_unlock RETURN
    wake_lock

    (
        cd /data/data/com.termux/files
        tar --use-compress-program="$comp" -cpf "$filepath" \
            --exclude='./home/storage' \
            --exclude='./home/.cache' \
            --exclude='./usr/var/cache/apt/archives' \
            --exclude='./usr/tmp' \
            ./home ./usr
    ) &

    if spinner $! "Creating full backup"; then
        if [ -f "$filepath" ]; then
            write_checksum "$filepath"
            ln -sf "$filepath" "$LATEST_FULL"
            local size; size=$(du -h "$filepath" | cut -f1)
            echo -e "\n  ${G}✅ Full Backup Successful!${NC}"
            echo -e "  ${G}📁 File:${NC}    ${filename}"
            echo -e "  ${G}📊 Size:${NC}    ${size}"
            echo -e "  ${G}🔒 Checksum:${NC} saved (${filename}.sha256)"
            echo -e "  ${G}🔗 Latest:${NC}   LATEST_FULL.tar.gz → ${filename}"
            log "Full backup created: ${filename} (${size})"
            notify "Titanium Backup" "Full backup complete (${size})"
            prune_backups "termux-full-*.tar.gz" "full"
        else
            echo -e "\n  ${R}❌ Backup file not created!${NC}"
        fi
    else
        echo -e "\n  ${R}❌ Backup failed!${NC}"
        log "Full backup FAILED"
        notify "Titanium Backup" "Full backup failed"
        rm -f "$filepath" 2>/dev/null || true
    fi

    pause $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 2. SELECTIVE BACKUP
#-----------------------------------------------------------
do_selective_backup() {
    header
    echo -e "  ${C}📦 SELECTIVE BACKUP MODE${NC}\n"
    check_battery || { pause $'\n  🔙 Press Enter to return...'; return; }

    local folder="selective-${TIMESTAMP}"
    local workdir="${BACKUP_DIR}/${folder}"
    mkdir -p "$workdir"
    local comp; comp=$(get_compressor)

    trap wake_unlock RETURN
    wake_lock

    echo -e "  ${Y}📋 Generating package list...${NC}"
    pkg list-installed 2>/dev/null | cut -d/ -f1 > "${workdir}/packages-list.txt"
    local pkg_count; pkg_count=$(wc -l < "${workdir}/packages-list.txt" | tr -d ' ')
    echo -e "  ${G}   ✓ ${pkg_count} packages listed${NC}"

    echo -e "  ${Y}📂 Backing up configs & scripts...${NC}"
    (
        cd "$HOME"
        tar --use-compress-program="$comp" -cf "${workdir}/home-configs.tar.gz" \
            .bashrc .zshrc .profile .termux .config .ssh \
            bin scripts .local 2>/dev/null || true
    ) &
    spinner $! "Archiving home directory"

    cat > "${workdir}/backup-info.txt" <<EOF
TITANIUM BACKUP — Selective Archive
Created: $(date)
Packages: ${pkg_count}
Hostname: $(hostname)
EOF

    local final="${BACKUP_DIR}/termux-selective-${TIMESTAMP}.tar.gz"
    (
        cd "$BACKUP_DIR"
        tar --use-compress-program="$comp" -cf "$final" "$(basename "$workdir")"
        rm -rf "$workdir"
    ) &
    spinner $! "Finalizing archive"

    if [ -f "$final" ]; then
        write_checksum "$final"
        ln -sf "$final" "$LATEST_SELECTIVE"
        local size; size=$(du -h "$final" | cut -f1)
        echo -e "\n  ${G}✅ Selective Backup Successful!${NC}"
        echo -e "  ${G}📁 File:${NC}    $(basename "$final")"
        echo -e "  ${G}📊 Size:${NC}    ${size}"
        echo -e "  ${G}📦 Packages:${NC} ${pkg_count}"
        echo -e "  ${G}🔒 Checksum:${NC} saved"
        log "Selective backup created: $(basename "$final") (${size}, ${pkg_count} packages)"
        notify "Titanium Backup" "Selective backup complete (${pkg_count} packages)"
        prune_backups "termux-selective-*.tar.gz" "selective"
    else
        echo -e "\n  ${R}❌ Selective backup failed!${NC}"
        log "Selective backup FAILED"
        notify "Titanium Backup" "Selective backup failed"
    fi

    pause $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 3. FULL RESTORE
#-----------------------------------------------------------
do_full_restore() {
    header
    echo -e "  ${C}♻️  FULL RESTORE MODE${NC}\n"

    local backups=()
    while IFS= read -r line; do backups+=("$line"); done < <(ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null || true)

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "  ${R}❌ No full backups found!${NC}"
        pause $'\n  🔙 Press Enter to return...'
        return
    fi

    echo -e "  ${Y}📂 Available Full Backups:${NC}\n"
    local i=1
    for b in "${backups[@]}"; do
        local size; size=$(du -h "$b" | cut -f1)
        local name; name=$(basename "$b")
        local mark=""
        if verify_checksum "$b"; then mark=" ${G}✓ verified${NC}"; fi
        echo -e "  ${G}[$i]${NC} ${name} ${Y}(${size})${NC}${mark}"
        ((i++))
    done

    if [ -L "$LATEST_FULL" ]; then
        local latest_target; latest_target=$(readlink "$LATEST_FULL" 2>/dev/null || echo "none")
        [ -f "$latest_target" ] && echo -e "\n  ${G}[L]${NC} Latest → ${Y}$(basename "$latest_target")${NC}"
    fi

    echo -e "  ${R}[0]${NC} Cancel"
    echo ""
    read -r -p "  👉 Select backup [1-$((i - 1))/L/0]: " choice

    local target=""
    if [[ "$choice" == "0" ]]; then return
    elif [[ "$choice" =~ ^[Ll]$ ]]; then target="$LATEST_FULL"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        target="${backups[$((choice - 1))]}"
    else
        echo -e "\n  ${R}❌ Invalid option!${NC}"
        sleep 1; return
    fi

    if [ ! -f "$target" ]; then
        echo -e "\n  ${R}❌ Backup file not found!${NC}"
        sleep 1; return
    fi

    echo -e "\n  ${Y}📂 Selected:${NC} $(basename "$(readlink -f "$target")")"

    echo -e "  ${Y}🔍 Checking archive integrity...${NC}"
    if ! tar -tzf "$target" >/dev/null 2>&1; then
        echo -e "  ${R}❌ Archive appears corrupt — aborting restore for your safety.${NC}"
        pause $'\n  🔙 Press Enter to return...'
        return
    fi
    if verify_checksum "$target"; then
        echo -e "  ${G}✓ Checksum verified${NC}"
    else
        echo -e "  ${Y}⚠️  No/failed checksum match — archive itself reads OK, proceed with care${NC}"
    fi

    if ! confirm_danger; then
        echo -e "\n  ${Y}❌ Cancelled${NC}"
        sleep 1; return
    fi

    # Safety net: snapshot the CURRENT environment to its own file before touching anything.
    # (We deliberately do NOT rename home/usr out of the way before extracting — tar, mv, sleep,
    # and bash itself all live inside usr/bin, so renaming usr away breaks every command needed
    # to finish the restore, including tar. Extracting directly on top is the same safe pattern
    # `pkg upgrade` uses to replace tar/bash/libc while they're running.)
    local snapshot="${BACKUP_DIR}/pre-restore-snapshot-${TIMESTAMP}.tar.gz"
    echo -e "  ${Y}📸 Saving a safety snapshot of your current setup first...${NC}"
    (
        cd /data/data/com.termux/files
        tar --use-compress-program="$(get_compressor)" -cpf "$snapshot" \
            --exclude='./home/storage' --exclude='./home/.cache' \
            --exclude='./usr/var/cache/apt/archives' --exclude='./usr/tmp' \
            ./home ./usr
    ) &
    if spinner $! "Snapshotting current environment"; then
        write_checksum "$snapshot"
        echo -e "  ${DIM}   Saved to $(basename "$snapshot") — restore this manually if today's restore goes wrong.${NC}"
    else
        echo -e "  ${Y}⚠️  Could not create a safety snapshot (continuing anyway)${NC}"
        rm -f "$snapshot" 2>/dev/null || true
    fi

    echo -e "\n  ${Y}⏳ Restoring...${NC}"
    echo -e "  ${R}🛑 Do NOT close this window!${NC}\n"

    trap wake_unlock RETURN
    wake_lock

    (
        cd /data/data/com.termux/files
        tar --use-compress-program="$(get_compressor)" -xpf "$target"
    ) &

    if spinner $! "Restoring full backup"; then
        echo -e "\n  ${G}✅ Restore Successful!${NC}"
        echo -e "  ${G}🎉 Termux is back to exactly how it was!${NC}"
        echo -e "\n  ${R}⚠️  IMPORTANT:${NC}"
        echo -e "  ${Y}   Close Termux completely and reopen it.${NC}"
        echo -e "  ${Y}   Do NOT run any commands before restarting.${NC}"
        log "Full restore completed from $(basename "$target")"
        notify "Titanium Backup" "Restore complete — please restart Termux"
    else
        echo -e "\n  ${R}❌ Restore failed partway through.${NC}"
        echo -e "  ${Y}💡 Your environment may be in a mixed state. If Termux misbehaves,${NC}"
        echo -e "  ${Y}   restore from the safety snapshot: $(basename "$snapshot")${NC}"
        echo -e "  ${Y}💡 Also check if /sdcard has enough free space.${NC}"
        log "Full restore FAILED from $(basename "$target")"
        notify "Titanium Backup" "Restore failed — see snapshot"
    fi

    pause $'\n  🔙 Press Enter to return (but restart Termux first)...'
}

#-----------------------------------------------------------
# 4. SELECTIVE RESTORE
#-----------------------------------------------------------
do_selective_restore() {
    header
    echo -e "  ${C}🔧 SELECTIVE RESTORE MODE${NC}\n"

    local backups=()
    while IFS= read -r line; do backups+=("$line"); done < <(ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null || true)

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "  ${R}❌ No selective backups found!${NC}"
        pause $'\n  🔙 Press Enter to return...'
        return
    fi

    echo -e "  ${Y}📂 Available Selective Backups:${NC}\n"
    local i=1
    for b in "${backups[@]}"; do
        local size; size=$(du -h "$b" | cut -f1)
        echo -e "  ${G}[$i]${NC} $(basename "$b") ${Y}(${size})${NC}"
        ((i++))
    done

    if [ -L "$LATEST_SELECTIVE" ]; then
        local lt; lt=$(readlink "$LATEST_SELECTIVE" 2>/dev/null || echo "")
        [ -f "$lt" ] && echo -e "\n  ${G}[L]${NC} Latest → ${Y}$(basename "$lt")${NC}"
    fi

    echo -e "  ${R}[0]${NC} Cancel"
    echo ""
    read -r -p "  👉 Select backup [1-$((i - 1))/L/0]: " choice

    local target=""
    if [[ "$choice" == "0" ]]; then return
    elif [[ "$choice" =~ ^[Ll]$ ]]; then target="$LATEST_SELECTIVE"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        target="${backups[$((choice - 1))]}"
    else
        echo -e "\n  ${R}❌ Invalid option!${NC}"
        sleep 1; return
    fi

    if [ ! -f "$target" ]; then
        echo -e "\n  ${R}❌ File not found!${NC}"
        sleep 1; return
    fi

    echo -e "\n  ${Y}⏳ Starting selective restore...${NC}"

    local tmpdir="${BACKUP_DIR}/.restore-tmp-${TIMESTAMP}"
    mkdir -p "$tmpdir"

    (cd "$tmpdir" && tar --use-compress-program="$(get_compressor)" -xf "$target") &
    spinner $! "Extracting archive"

    local inner=""
    for d in "$tmpdir"/*/; do inner="${d%/}"; break; done

    if [ -z "$inner" ] || [ ! -d "$inner" ]; then
        echo -e "\n  ${R}❌ Invalid backup structure!${NC}"
        rm -rf "$tmpdir"
        sleep 1; return
    fi

    if [ -f "${inner}/packages-list.txt" ]; then
        local pkg_count; pkg_count=$(wc -l < "${inner}/packages-list.txt" | tr -d ' ')
        echo -e "\n  ${Y}📦 ${pkg_count} packages to install...${NC}"
        echo -e "  ${G}[1]${NC} Fast batch install ${DIM}(one command, quicker, less detail)${NC}"
        echo -e "  ${G}[2]${NC} One-by-one ${DIM}(see status per package)${NC}"
        read -r -p "  👉 Choose [1/2] (default 2): " pkg_mode

        if [[ "$pkg_mode" == "1" ]]; then
            echo -e "\n  ${Y}⏳ Installing all packages in one batch...${NC}"
            xargs -a "${inner}/packages-list.txt" pkg install -y >/dev/null 2>&1 &
            spinner $! "Batch installing ${pkg_count} packages"
        else
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
    fi

    if [ -f "${inner}/home-configs.tar.gz" ]; then
        echo -e "\n  ${Y}📂 Restoring home configs...${NC}"
        (cd "$HOME" && tar --use-compress-program="$(get_compressor)" -xf "${inner}/home-configs.tar.gz" 2>/dev/null || true) &
        spinner $! "Applying configs"
    fi

    rm -rf "$tmpdir"

    echo -e "\n  ${G}✅ Selective Restore Complete!${NC}"
    echo -e "  ${G}🔧 Packages & configs are back to their previous state.${NC}"
    log "Selective restore completed from $(basename "$target")"
    notify "Titanium Backup" "Selective restore complete"

    pause $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 5. LIST BACKUPS
#-----------------------------------------------------------
list_backups() {
    header
    echo -e "  ${C}📋 BACKUP INVENTORY${NC}\n"
    echo -e "  ${BOLD}${P}📂 Location:${NC} ${BACKUP_DIR}\n"

    echo -e "  ${Y}🗄️  Full Backups:${NC}"
    local full_count=0
    for f in "${BACKUP_DIR}"/termux-full-*.tar.gz; do
        [ -f "$f" ] || continue
        local size; size=$(du -h "$f" | cut -f1)
        local date; date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        local name; name=$(basename "$f")
        local marker=""
        [ "$f" == "$(readlink -f "$LATEST_FULL" 2>/dev/null || true)" ] && marker=" ${G}← LATEST${NC}"
        echo -e "  ${G}  •${NC} ${name} ${Y}[${size}]${NC} ${C}${date}${NC}${marker}"
        ((full_count++)) || true
    done
    [ "$full_count" -eq 0 ] && echo -e "  ${R}  (none)${NC}"

    echo ""

    echo -e "  ${Y}📦 Selective Backups:${NC}"
    local sel_count=0
    for f in "${BACKUP_DIR}"/termux-selective-*.tar.gz; do
        [ -f "$f" ] || continue
        local size; size=$(du -h "$f" | cut -f1)
        local date; date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1)
        local name; name=$(basename "$f")
        local marker=""
        [ "$f" == "$(readlink -f "$LATEST_SELECTIVE" 2>/dev/null || true)" ] && marker=" ${G}← LATEST${NC}"
        echo -e "  ${G}  •${NC} ${name} ${Y}[${size}]${NC} ${C}${date}${NC}${marker}"
        ((sel_count++)) || true
    done
    [ "$sel_count" -eq 0 ] && echo -e "  ${R}  (none)${NC}"

    echo ""
    echo -e "  ${BOLD}Total:${NC} ${G}${full_count}${NC} Full + ${G}${sel_count}${NC} Selective"
    local total; total=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo -e "  ${BOLD}Disk Used:${NC} ${Y}${total}${NC}"

    pause $'\n  🔙 Press Enter to return to menu...'
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
    read -r -p "  👉 Option: " del_choice

    case "$del_choice" in
        1)
            echo ""
            ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f" "${f}.sha256"
                echo -e "  ${R}🗑️  Deleted:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ Old full backups cleaned up${NC}"
            ;;
        2)
            echo ""
            ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f" "${f}.sha256"
                echo -e "  ${R}🗑️  Deleted:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ Old selective backups cleaned up${NC}"
            ;;
        3)
            echo ""
            ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f" "${f}.sha256"; echo -e "  ${R}🗑️  Full:${NC} $(basename "$f")"
            done
            ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null | tail -n +4 | while read -r f; do
                rm -f "$f" "${f}.sha256"; echo -e "  ${R}🗑️  Selective:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ All old backups cleaned up${NC}"
            ;;
        4)
            echo ""
            read -r -p "  Type 'DELETE' to remove ALL backups: " confirm
            if [ "$confirm" == "DELETE" ]; then
                rm -f "${BACKUP_DIR}"/termux-*.tar.gz "${BACKUP_DIR}"/termux-*.sha256
                rm -f "${BACKUP_DIR}"/LATEST_*.tar.gz
                echo -e "\n  ${G}✅ All backups deleted${NC}"
                log "All backups deleted by user"
            else
                echo -e "\n  ${Y}❌ Cancelled${NC}"
            fi
            ;;
        *)
            echo -e "\n  ${Y}❌ Cancelled${NC}"
            ;;
    esac

    pause $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 7. QUICK BACKUP (Silent Mode — cron friendly)
#-----------------------------------------------------------
quick_backup() {
    header
    echo -e "  ${C}⚡ QUICK SILENT BACKUP${NC}\n"

    local filename="termux-full-${TIMESTAMP}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"
    local comp; comp=$(get_compressor)

    echo -e "  ${Y}⏳ Running silent backup...${NC}"
    echo -e "  ${DIM}No prompts, no spinners — just pure speed.${NC}\n"

    wake_lock
    cd /data/data/com.termux/files
    if tar --use-compress-program="$comp" -cpf "$filepath" \
        --exclude='./home/storage' \
        --exclude='./home/.cache' \
        --exclude='./usr/var/cache/apt/archives' \
        --exclude='./usr/tmp' \
        ./home ./usr; then

        write_checksum "$filepath"
        ln -sf "$filepath" "$LATEST_FULL"
        local size; size=$(du -h "$filepath" | cut -f1)
        echo -e "  ${G}✅ Quick Backup Done!${NC}"
        echo -e "  ${G}📊 Size:${NC} ${size}"
        echo -e "  ${G}📁 File:${NC} ${filename}"
        log "Quick backup created: ${filename} (${size})"
        notify "Titanium Backup" "Quick backup complete (${size})"
        prune_backups "termux-full-*.tar.gz" "full"
    else
        echo -e "  ${R}❌ Quick backup failed!${NC}"
        log "Quick backup FAILED"
        notify "Titanium Backup" "Quick backup failed"
        rm -f "$filepath" 2>/dev/null || true
    fi
    wake_unlock

    [ -t 0 ] && sleep 2 || true
}

#-----------------------------------------------------------
# 8. VERIFY BACKUPS
#-----------------------------------------------------------
verify_backups() {
    header
    echo -e "  ${C}🔍 VERIFY BACKUP INTEGRITY${NC}\n"

    local files=()
    while IFS= read -r line; do files+=("$line"); done < <(ls -1t "${BACKUP_DIR}"/termux-*.tar.gz 2>/dev/null || true)

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "  ${R}❌ No backups found${NC}"
        pause $'\n  🔙 Press Enter to return...'
        return
    fi

    for f in "${files[@]}"; do
        printf "  ${C}%-45s${NC}" "$(basename "$f")"
        if tar -tzf "$f" >/dev/null 2>&1; then
            if verify_checksum "$f"; then
                echo -e "${G} ✅ archive OK, checksum verified${NC}"
            else
                echo -e "${Y} ⚠️  archive OK, no/failed checksum${NC}"
            fi
        else
            echo -e "${R} ❌ CORRUPT — do not restore from this file${NC}"
        fi
    done

    pause $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# 9. SETTINGS
#-----------------------------------------------------------
open_settings() {
    header
    echo -e "  ${C}⚙️  SETTINGS${NC}\n"
    echo -e "  ${Y}Config file:${NC} ${CONFIG_FILE}\n"
    echo -e "  ${DIM}BACKUP_DIR=${BACKUP_DIR}${NC}"
    echo -e "  ${DIM}KEEP_COUNT=${KEEP_COUNT}${NC}"
    echo -e "  ${DIM}AUTO_PRUNE=${AUTO_PRUNE}${NC}"
    echo -e "  ${DIM}LOW_BATTERY_THRESHOLD=${LOW_BATTERY_THRESHOLD}${NC}\n"

    local editor="${EDITOR:-nano}"
    if [ -t 0 ] && command -v "$editor" >/dev/null 2>&1; then
        read -r -p "  Open in ${editor}? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            "$editor" "$CONFIG_FILE"
            echo -e "\n  ${G}✅ Saved. Restart the script to apply changes.${NC}"
        fi
    else
        echo -e "  ${DIM}Edit ${CONFIG_FILE} manually, then restart the script.${NC}"
    fi

    pause $'\n  🔙 Press Enter to return to menu...'
}

#-----------------------------------------------------------
# CLI (non-interactive) mode for cron / automation
#-----------------------------------------------------------
show_help() {
cat <<EOF
Titanium Backup v${VERSION}

Usage: ${SCRIPT_NAME} [option]

  --full, --quick, 7   Run a full backup silently (cron-friendly)
  --selective          Run a selective backup silently
  --list               List all backups
  --prune              Prune old backups per KEEP_COUNT
  --verify             Verify integrity of all backups
  -h, --help           Show this help

Run with no arguments for the interactive menu.
Restore is interactive-only, by design — it's destructive.
EOF
}

#-----------------------------------------------------------
# MAIN LOOP
#-----------------------------------------------------------
main() {
    check_storage

    case "${1:-}" in
        -h|--help) show_help; exit 0 ;;
        --full|--quick|7) quick_backup; exit 0 ;;
        --selective) do_selective_backup; exit 0 ;;
        --list) list_backups; exit 0 ;;
        --prune) prune_backups "termux-full-*.tar.gz" "full"; prune_backups "termux-selective-*.tar.gz" "selective"; exit 0 ;;
        --verify) verify_backups; exit 0 ;;
    esac

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
            8) verify_backups ;;
            9) open_settings ;;
            0)
                header
                echo -e "\n  ${G}👋 Thanks for using TITANIUM BACKUP!${NC}"
                echo -e "  ${DIM}github.com/iaemonbd/TITANIUM-BACKUP${NC}\n"
                exit 0
                ;;
            *)
                echo -e "  ${R}❌ Invalid option! Please enter 0-9${NC}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
