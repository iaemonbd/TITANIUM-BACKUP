#!/data/data/com.termux/files/usr/bin/bash

#=============================================================
#  Termux Intelligent Backup & Restore Manager
#  Location: /sdcard (Internal Storage)
#=============================================================

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; P='\033[0;35m'; NC='\033[0m'
BOLD='\033[1m'

# Config
BACKUP_DIR="/sdcard/termux-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LATEST_LINK="${BACKUP_DIR}/LATEST_FULL.tar.gz"
LATEST_SELECTIVE="${BACKUP_DIR}/LATEST_SELECTIVE.tar.gz"

# Ensure backup dir exists
mkdir -p "$BACKUP_DIR" 2>/dev/null

#-----------------------------------------------------------
# Helper Functions
#-----------------------------------------------------------

check_storage() {
    if [ ! -d "/sdcard" ] || [ ! -w "/sdcard" ]; then
        echo -e "${R}❌ Error: /sdcard access নেই!${NC}"
        echo -e "${Y}👉 প্রথমে চালান: termux-setup-storage${NC}"
        exit 1
    fi
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi
}

header() {
    clear
    echo -e "${C}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC}  ${BOLD}${P}  Termux Intelligent Backup & Restore Manager${NC}     ${C}║${NC}"
    echo -e "${C}║${NC}       ${Y}Backup Location: /sdcard/termux-backups${NC}       ${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_menu() {
    echo -e "  ${G}[1]${NC} 🗄️  Full Backup (Complete Termux)"
    echo -e "  ${G}[2]${NC} 📦 Selective Backup (Packages + Configs + Scripts)"
    echo -e "  ${G}[3]${NC} ♻️  Full Restore (from Latest or Choose)"
    echo -e "  ${G}[4]${NC} 🔧 Selective Restore (Packages + Configs only)"
    echo -e "  ${G}[5]${NC} 📋 List All Backups"
    echo -e "  ${G}[6]${NC} 🗑️  Delete Old Backups"
    echo -e "  ${G}[7]${NC} ⚡ Quick Backup (Silent Full Backup)"
    echo -e "  ${R}[0]${NC} ❌ Exit"
    echo ""
    echo -ne "  ${Y}👉 আপনার অপশন নির্বাচন করুন [0-7]: ${NC}"
}

spinner() {
    local pid=$1; local msg="$2"
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 7); do
            printf "\r  ${Y}%s %s${NC}" "${spin:$i:1}" "$msg"
            sleep 0.1
        done
    done
    printf "\r  ${G}✓ %s${NC}\n" "$msg"
}

#-----------------------------------------------------------
# 1. FULL BACKUP
#-----------------------------------------------------------
do_full_backup() {
    header
    echo -e "${C}  🗄️  FULL BACKUP MODE${NC}\n"
    
    local filename="termux-full-${TIMESTAMP}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"
    
    echo -e "  ${Y}📂 Destination:${NC} ${filepath}"
    echo -e "  ${Y}⏳ Backup শুরু হচ্ছে...${NC}\n"
    
    # Run tar in background with progress
    (
        cd /data/data/com.termux/files
        tar -czpf "$filepath" \
            --exclude='./home/storage' \
            --exclude='./home/.cache' \
            --exclude='./usr/var/cache/apt/archives' \
            --exclude='./usr/tmp' \
            ./home ./usr
    ) &
    spinner $! "Full Backup হচ্ছে..."
    
    if [ -f "$filepath" ]; then
        local size=$(du -h "$filepath" | cut -f1)
        ln -sf "$filepath" "$LATEST_LINK"
        echo -e "\n  ${G}✅ Full Backup সফল!${NC}"
        echo -e "  ${G}📁 File:${NC} ${filename}"
        echo -e "  ${G}📊 Size:${NC} ${size}"
        echo -e "  ${G}🔗 Latest Link Updated${NC}"
    else
        echo -e "\n  ${R}❌ Backup ব্যর্থ!${NC}"
    fi
    read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
}

#-----------------------------------------------------------
# 2. SELECTIVE BACKUP
#-----------------------------------------------------------
do_selective_backup() {
    header
    echo -e "${C}  📦 SELECTIVE BACKUP MODE${NC}\n"
    
    local folder="selective-${TIMESTAMP}"
    local workdir="${BACKUP_DIR}/${folder}"
    mkdir -p "$workdir"
    
    echo -e "  ${Y}📋 প্যাকেজ লিস্ট তৈরি হচ্ছে...${NC}"
    pkg list-installed 2>/dev/null | cut -d/ -f1 > "${workdir}/packages-list.txt"
    local pkg_count=$(wc -l < "${workdir}/packages-list.txt")
    echo -e "  ${G}   ✓ ${pkg_count}টি প্যাকেজ লিস্টেড${NC}"
    
    echo -e "  ${Y}📂 কনফিগারেশন ও স্ক্রিপ্ট ব্যাকআপ হচ্ছে...${NC}"
    
    # Create selective tar from home
    (
        cd "$HOME"
        tar -czf "${workdir}/home-configs.tar.gz" \
            .bashrc .zshrc .profile .termux .config .ssh \
            bin scripts .local 2>/dev/null
    ) &
    spinner $! "Configs সংগ্রহ হচ্ছে..."
    
    # Create info file
    cat > "${workdir}/backup-info.txt" <<EOF
Termux Selective Backup
Created: $(date)
Packages: ${pkg_count}
EOF
    
    # Final tar of the folder
    local final="${BACKUP_DIR}/termux-selective-${TIMESTAMP}.tar.gz"
    (
        cd "$BACKUP_DIR"
        tar -czf "$final" "$(basename "$workdir")"
        rm -rf "$workdir"
    ) &
    spinner $! "Archive finalize হচ্ছে..."
    
    if [ -f "$final" ]; then
        ln -sf "$final" "$LATEST_SELECTIVE"
        local size=$(du -h "$final" | cut -f1)
        echo -e "\n  ${G}✅ Selective Backup সফল!${NC}"
        echo -e "  ${G}📁 File:${NC} $(basename "$final")"
        echo -e "  ${G}📊 Size:${NC} ${size}"
    else
        echo -e "\n  ${R}❌ Selective Backup ব্যর্থ!${NC}"
    fi
    read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
}

#-----------------------------------------------------------
# 3. FULL RESTORE
#-----------------------------------------------------------
do_full_restore() {
    header
    echo -e "${C}  ♻️  FULL RESTORE MODE${NC}\n"
    
    # List available full backups
    local backups=($(ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ] || [ -z "${backups[0]}" ]; then
        echo -e "  ${R}❌ কোনো Full Backup পাওয়া যায়নি!${NC}"
        read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
        return
    fi
    
    echo -e "  ${Y}📂 উপলব্ধ Full Backups:${NC}\n"
    local i=1
    for b in "${backups[@]}"; do
        local size=$(du -h "$b" | cut -f1)
        local name=$(basename "$b")
        echo -e "  ${G}[$i]${NC} ${name} ${Y}(${size})${NC}"
        ((i++))
    done
    echo -e "  ${G}[L]${NC} Latest (সর্বশেষ: $(basename "$(readlink "$LATEST_LINK")"))"
    echo -e "  ${R}[0]${NC} Cancel"
    echo ""
    
    read -p "  👉 কোনটি রিস্টোর করবেন [1-$((i-1))/L/0]: " choice
    
    local target=""
    if [[ "$choice" == "0" ]]; then return
    elif [[ "$choice" =~ ^[Ll]$ ]]; then target="$LATEST_LINK"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        target="${backups[$((choice-1))]}"
    else
        echo -e "\n  ${R}❌ ভুল অপশন!${NC}"
        sleep 1; return
    fi
    
    # Verify target
    if [ ! -f "$target" ]; then
        echo -e "\n  ${R}❌ ফাইল পাওয়া যায়নি!${NC}"
        sleep 1; return
    fi
    
    echo ""
    echo -e "  ${R}⚠️  সতর্কতা: এটি বর্তমান Termux ডাটা ওভাররাইট করবে!${NC}"
    echo -e "  ${Y}💡 পরামর্শ: নতুন ইনস্টলের পর Clear Data করে নিন${NC}"
    read -p "  ❓ আপনি কি নিশ্চিত? [yes/N]: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo -e "\n  ${Y}❌ বাতিল করা হয়েছে${NC}"
        sleep 1; return
    fi
    
    echo -e "\n  ${Y}⏳ Full Restore শুরু হচ্ছে...${NC}"
    echo -e "  ${Y}📂 Source:${NC} $(basename "$(readlink -f "$target")")"
    
    # Stop all termux sessions warning
    echo -e "  ${R}🛑 Termux বন্ধ করে দেওয়া হচ্ছে (পরেরবার খুললেই ready)...${NC}"
    
    (
        cd /data/data/com.termux/files
        # Remove old (keep as backup just in case)
        mv home home.old.$(date +%s) 2>/dev/null
        mv usr usr.old.$(date +%s) 2>/dev/null
        
        # Extract
        tar -xzpf "$target"
        
        # Cleanup old backups
        rm -rf home.old.* usr.old.* 2>/dev/null
    ) &
    spinner $! "Restoring..."
    
    echo -e "\n  ${G}✅ Full Restore সম্পন্ন!${NC}"
    echo -e "  ${G}🎉 Termux আবার আগের মতো!${NC}"
    echo -e "\n  ${Y}⚠️  এখন অবশ্যই Termux বন্ধ করে আবার খুলুন${NC}"
    echo -e "  ${Y}   অথবা 'exit' দিয়ে বের হয়ে আসুন${NC}"
    
    read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন (তবে restart দেওয়া ভালো)...'
}

#-----------------------------------------------------------
# 4. SELECTIVE RESTORE
#-----------------------------------------------------------
do_selective_restore() {
    header
    echo -e "${C}  🔧 SELECTIVE RESTORE MODE${NC}\n"
    
    local backups=($(ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ] || [ -z "${backups[0]}" ]; then
        echo -e "  ${R}❌ কোনো Selective Backup পাওয়া যায়নি!${NC}"
        read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
        return
    fi
    
    echo -e "  ${Y}📂 উপলব্ধ Selective Backups:${NC}\n"
    local i=1
    for b in "${backups[@]}"; do
        local size=$(du -h "$b" | cut -f1)
        echo -e "  ${G}[$i]${NC} $(basename "$b") ${Y}(${size})${NC}"
        ((i++))
    done
    echo -e "  ${G}[L]${NC} Latest"
    echo -e "  ${R}[0]${NC} Cancel"
    echo ""
    
    read -p "  👉 কোনটি রিস্টোর করবেন [1-$((i-1))/L/0]: " choice
    
    local target=""
    if [[ "$choice" == "0" ]]; then return
    elif [[ "$choice" =~ ^[Ll]$ ]]; then target="$LATEST_SELECTIVE"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        target="${backups[$((choice-1))]}"
    else
        echo -e "\n  ${R}❌ ভুল অপশন!${NC}"
        sleep 1; return
    fi
    
    if [ ! -f "$target" ]; then
        echo -e "\n  ${R}❌ ফাইল পাওয়া যায়নি!${NC}"
        sleep 1; return
    fi
    
    echo -e "\n  ${Y}⏳ Selective Restore শুরু হচ্ছে...${NC}"
    
    # Create temp dir
    local tmpdir="${BACKUP_DIR}/.restore-tmp-${TIMESTAMP}"
    mkdir -p "$tmpdir"
    
    # Extract selective archive
    (
        cd "$tmpdir"
        tar -xzf "$target"
    ) &
    spinner $! "Archive extract হচ্ছে..."
    
    # Find the inner folder
    local inner=$(find "$tmpdir" -maxdepth 1 -type d | tail -1)
    
    # Restore packages
    if [ -f "${inner}/packages-list.txt" ]; then
        local pkg_count=$(wc -l < "${inner}/packages-list.txt")
        echo -e "\n  ${Y}📦 ${pkg_count}টি প্যাকেজ ইনস্টল হচ্ছে...${NC}"
        echo -e "  ${Y}   (এটি সময় নিতে পারে)${NC}\n"
        
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            echo -ne "  ${C}  → ${pkg}...${NC}"
            pkg install -y "$pkg" >/dev/null 2>&1 && echo -e "${G} OK${NC}" || echo -e "${R} FAIL${NC}"
        done < "${inner}/packages-list.txt"
    fi
    
    # Restore configs
    if [ -f "${inner}/home-configs.tar.gz" ]; then
        echo -e "\n  ${Y}📂 Home configs রিস্টোর হচ্ছে...${NC}"
        (
            cd "$HOME"
            tar -xzf "${inner}/home-configs.tar.gz"
        ) &
        spinner $! "Configs restore হচ্ছে..."
    fi
    
    # Cleanup
    rm -rf "$tmpdir"
    
    echo -e "\n  ${G}✅ Selective Restore সম্পন্ন!${NC}"
    echo -e "  ${G}🔧 প্যাকেজ ও কনফিগারেশন আগের মতো হয়ে গেছে${NC}"
    
    read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
}

#-----------------------------------------------------------
# 5. LIST BACKUPS
#-----------------------------------------------------------
list_backups() {
    header
    echo -e "${C}  📋 BACKUP INVENTORY${NC}\n"
    
    echo -e "  ${BOLD}${P}📂 Location: ${BACKUP_DIR}${NC}\n"
    
    # Full backups
    echo -e "  ${Y}🗄️  Full Backups:${NC}"
    local full_count=0
    for f in "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null; do
        [ -f "$f" ] || continue
        local size=$(du -h "$f" | cut -f1)
        local date=$(stat -c %y "$f" 2>/dev/null | cut -d' ' -f1)
        echo -e "  ${G}  •${NC} $(basename "$f") ${Y}[${size}]${NC} ${C}${date}${NC}"
        ((full_count++))
    done
    [ "$full_count" -eq 0 ] && echo -e "  ${R}  (কোনো Full Backup নেই)${NC}"
    
    echo ""
    
    # Selective backups
    echo -e "  ${Y}📦 Selective Backups:${NC}"
    local sel_count=0
    for f in "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null; do
        [ -f "$f" ] || continue
        local size=$(du -h "$f" | cut -f1)
        local date=$(stat -c %y "$f" 2>/dev/null | cut -d' ' -f1)
        echo -e "  ${G}  •${NC} $(basename "$f") ${Y}[${size}]${NC} ${C}${date}${NC}"
        ((sel_count++))
    done
    [ "$sel_count" -eq 0 ] && echo -e "  ${R}  (কোনো Selective Backup নেই)${NC}"
    
    echo ""
    echo -e "  ${BOLD}মোট: ${G}${full_count}${NC} Full + ${G}${sel_count}${NC} Selective${NC}"
    
    # Disk usage
    local total=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    echo -e "  ${BOLD}মোট ব্যবহৃত স্পেস: ${Y}${total}${NC}"
    
    read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
}

#-----------------------------------------------------------
# 6. DELETE OLD BACKUPS
#-----------------------------------------------------------
delete_old() {
    header
    echo -e "${C}  🗑️  DELETE OLD BACKUPS${NC}\n"
    
    echo -e "  ${Y}পুরনো ব্যাকআপ ডিলিট করুন:${NC}\n"
    echo -e "  ${G}[1]${NC} শুধু Full Backups (শেষ ৩টি রাখুন)"
    echo -e "  ${G}[2]${NC} শুধু Selective Backups (শেষ ৩টি রাখুন)"
    echo -e "  ${G}[3]${NC} সব পুরনো Backups (শেষ ৩টি করে রাখুন)"
    echo -e "  ${R}[4]${NC} সব Backup ডিলিট করুন (${R}সাবধান!${NC})"
    echo -e "  ${Y}[0]${NC} Cancel"
    echo ""
    
    read -p "  👉 অপশন: " del_choice
    
    case "$del_choice" in
        1)
            ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null | tail -n +4 | while read f; do
                rm -f "$f"
                echo -e "  ${R}🗑️  Deleted:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ পুরনো Full Backups ডিলিট হয়েছে${NC}"
            ;;
        2)
            ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null | tail -n +4 | while read f; do
                rm -f "$f"
                echo -e "  ${R}🗑️  Deleted:${NC} $(basename "$f")"
            done
            echo -e "\n  ${G}✅ পুরনো Selective Backups ডিলিট হয়েছে${NC}"
            ;;
        3)
            ls -1t "${BACKUP_DIR}"/termux-full-*.tar.gz 2>/dev/null | tail -n +4 | while read f; do rm -f "$f"; echo -e "  ${R}🗑️  Full:${NC} $(basename "$f")"; done
            ls -1t "${BACKUP_DIR}"/termux-selective-*.tar.gz 2>/dev/null | tail -n +4 | while read f; do rm -f "$f"; echo -e "  ${R}🗑️  Selective:${NC} $(basename "$f")"; done
            echo -e "\n  ${G}✅ পুরনো Backups ডিলিট হয়েছে${NC}"
            ;;
        4)
            read -p "  ${R}❓ সব Backup ডিলিট করবেন? লিখুন 'DELETE': ${NC}" confirm
            if [ "$confirm" == "DELETE" ]; then
                rm -f "${BACKUP_DIR}"/termux-*.tar.gz
                rm -f "${BACKUP_DIR}"/LATEST_*.tar.gz
                echo -e "\n  ${G}✅ সব Backup ডিলিট হয়েছে${NC}"
            else
                echo -e "\n  ${Y}❌ বাতিল${NC}"
            fi
            ;;
        *) echo -e "\n  ${Y}❌ বাতিল${NC}" ;;
    esac
    
    read -p $'\n  🔙 মেনুতে ফিরতে Enter চাপুন...'
}

#-----------------------------------------------------------
# 7. QUICK BACKUP
#-----------------------------------------------------------
quick_backup() {
    header
    echo -e "${C}  ⚡ QUICK SILENT BACKUP${NC}\n"
    
    local filename="termux-full-${TIMESTAMP}.tar.gz"
    local filepath="${BACKUP_DIR}/${filename}"
    
    echo -e "  ${Y}⏳ Silent backup চলছে...${NC}"
    
    cd /data/data/com.termux/files
    tar -czpf "$filepath" \
        --exclude='./home/storage' \
        --exclude='./home/.cache' \
        --exclude='./usr/var/cache/apt/archives' \
        --exclude='./usr/tmp' \
        ./home ./usr
    
    if [ -f "$filepath" ]; then
        ln -sf "$filepath" "$LATEST_LINK"
        local size=$(du -h "$filepath" | cut -f1)
        echo -e "\n  ${G}✅ Quick Backup সফল!${NC}"
        echo -e "  ${G}📊 Size:${NC} ${size}"
        echo -e "  ${G}📁 File:${NC} $(basename "$filepath")"
    else
        echo -e "\n  ${R}❌ ব্যর্থ!${NC}"
    fi
    
    sleep 2
}

#-----------------------------------------------------------
# MAIN LOOP
#-----------------------------------------------------------

check_storage

while true; do
    header
    show_menu
    read choice
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
            echo -e "\n  ${G}👋 Termux Backup Manager থেকে বের হচ্ছেন...${NC}\n"
            exit 0
            ;;
        *)
            echo -e "  ${R}❌ ভুল অপশন! 1-7 বা 0 দিন${NC}"
            sleep 1
            ;;
    esac
done
