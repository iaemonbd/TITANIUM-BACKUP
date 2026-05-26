I'll create a polished, modern README.md branded for your TITANIUM-BACKUP repo and save it for you.
Your updated TITANIUM BACKUP README.md is ready! Here's the modern version:

---

⚡ TITANIUM BACKUP

The Ultimate Termux Backup & Restore Manager

---

🎯 What is Titanium Backup?

TITANIUM BACKUP is a single, intelligent Bash script that turns your entire Termux environment into a portable archive. One backup today, full restoration tomorrow — no matter how many times you reinstall Termux.

> 🚀 Zero dependencies. Pure Bash. Battle-tested on Android 7 through 15.

---

✨ Features

	Feature	Description	
🗄️	Full System Backup	Complete snapshot of `home/` + `usr/` — every package, config, and dotfile	
📦	Selective Backup	Lightweight archive: package list + configs + scripts only	
♻️	One-Click Restore	Pick Latest or any previous backup from a dated list	
🔧	Selective Restore	Re-install packages & merge configs without wiping existing data	
📋	Backup Inventory	View all backups with size, date, and type in one glance	
🗑️	Smart Cleanup	Auto-delete old backups, keep only the last 3 of each type	
⚡	Silent Quick Mode	Background backup perfect for cron automation	
🎨	Modern TUI	Color-coded interface with spinners, progress bars, and emoji indicators	

---

📸 Preview

```
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║           ⚡ TITANIUM BACKUP & RESTORE MANAGER             ║
║                                                            ║
║              Storage: /sdcard/termux-backups               ║
╚════════════════════════════════════════════════════════════╝

  [1] 🗄️   Full Backup        — Complete Termux environment
  [2] 📦   Selective Backup   — Packages + Configs + Scripts
  [3] ♻️   Full Restore       — From Latest or Choose
  [4] 🔧   Selective Restore  — Packages & Configs only
  [5] 📋   List Backups       — View all with size & date
  [6] 🗑️   Delete Old         — Keep last 3, remove rest
  [7] ⚡   Quick Backup       — Silent mode for cron jobs
  [0] ❌   Exit

  👉 Select option [0-7]:
```

---

🚀 Installation

Method 1: Direct Download (Recommended)

```bash
# 1. Grant storage permission (first time only)
termux-setup-storage

# 2. Download the script
curl -L -o titanium-backup.sh https://raw.githubusercontent.com/iaemonbd/TITANIUM-BACKUP/main/titanium-backup.sh

# 3. Make it executable
chmod +x titanium-backup.sh

# 4. Launch
./titanium-backup.sh
```

Method 2: Git Clone

```bash
termux-setup-storage
pkg install git -y
git clone https://github.com/iaemonbd/TITANIUM-BACKUP.git
cd TITANIUM-BACKUP
chmod +x titanium-backup.sh
./titanium-backup.sh
```

---

📖 Usage Guide

🗄️ Full Backup
Perfect before any major system change or when your setup is "just right."

```bash
# Menu Option: 1
# Output: /sdcard/termux-backups/termux-full-20260526_223000.tar.gz
```

> 💡 A `LATEST_FULL.tar.gz` symlink is auto-updated so you never need to remember filenames.

---

📦 Selective Backup
Ideal for developers who version-control their dotfiles.

Includes:
- ✅ Installed package manifest (`packages-list.txt`)
- ✅ `.bashrc`, `.zshrc`, `.profile`
- ✅ `.termux/`, `.config/`, `.ssh/`
- ✅ `~/bin`, `~/scripts`

Excludes:
- ❌ Package binaries (re-installed later)
- ❌ Cache & temp files
- ❌ `~/storage` (Android symlink)

---

♻️ Full Restore
Use this when:
- Setting up a new phone
- After factory reset
- Termux stopped working and you reinstalled

```bash
# Pre-restore checklist:
# 1. Install Termux from F-Droid
# 2. Run: termux-setup-storage
# 3. Run script → Option 3
# 4. Choose "Latest" or a specific backup
# 5. Restart Termux when done
```

> ⚠️ Warning: Full restore overwrites all current Termux data. Make sure you really want to wipe before confirming.

---

🔧 Selective Restore
Use this when:
- Your Termux is working but you want your old packages & configs back
- You don't want to lose newly created files

```bash
# Menu Option: 4
# What happens:
#   1. Reads package-list.txt from backup
#   2. Runs: pkg install -y <each_package>
#   3. Extracts home configs into $HOME
```

---

📁 Backup Storage Structure

All backups are stored safely in your internal storage at `/sdcard/termux-backups`:

```
/sdcard/
└── 📂 termux-backups/
    ├── 🗄️  termux-full-20260526_223000.tar.gz        (1.2 GB)
    ├── 🗄️  termux-full-20260602_150045.tar.gz        (1.3 GB)
    ├── 📦 termux-selective-20260526_223500.tar.gz     (15 MB)
    ├── 📦 termux-selective-20260610_090012.tar.gz     (18 MB)
    ├── 🔗 LATEST_FULL.tar.gz → termux-full-20260602_150045.tar.gz
    └── 🔗 LATEST_SELECTIVE.tar.gz → termux-selective-20260610_090012.tar.gz
```

---

⚙️ Automation with Cron

Set up weekly automatic backups while you sleep:

```bash
# Install cronie
pkg install cronie -y

# Start crond
crond

# Edit crontab
crontab -e
```

Add this line for every Sunday at 3:00 AM:

```cron
0 3 * * 0 /data/data/com.termux/files/home/titanium-backup.sh <<< "7" >> /sdcard/termux-backup.log 2>&1
```

> ⚡ Option `7` triggers Quick (Silent) Backup — no menu, no prompts, fully automatic.

---

🛡️ Excluded Paths

These paths are automatically skipped to prevent bloated backups and restore issues:

Path	Reason	
`~/storage`	Android storage symlink — causes infinite recursion	
`~/.cache`	Temporary app caches	
`/usr/var/cache/apt/archives`	Redownloadable `.deb` files	
`/usr/tmp`	System temporary files	

---

🛠️ Requirements

- Android 7.0 (API 24) or higher
- Termux (latest from [F-Droid](https://f-droid.org/packages/com.termux/))
- Storage Permission (`termux-setup-storage`)
- Bash (pre-installed in Termux)

---

🐛 Troubleshooting

Problem	Solution	
`❌ /sdcard access নেই!`	Run `termux-setup-storage` and allow permission	
Restore failed / corrupted	Clear Termux data (`Settings → Apps → Termux → Clear Data`) then retry	
Backup size is 0 bytes	Check free space: `df -h /sdcard`	
Symlinks not working after restore	Restart Termux completely (swipe away from recents)	
`pkg install` fails during selective restore	Run `pkg update` manually first, then retry	

---

🤝 Contributing

Contributions make the open-source community amazing! Any contributions you make are greatly appreciated.

1. 🍴 Fork the Project
2. 🌿 Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. 💾 Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. 📤 Push to the Branch (`git push origin feature/AmazingFeature`)
5. 🔁 Open a Pull Request

---

📝 License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.

---

🌟 Star History

If you like this project, please consider giving it a ⭐ — it really helps!

---

Made with ❤️ in Bash for the Termux Community

[⬆ Back to Top](#-titanium-backup)

