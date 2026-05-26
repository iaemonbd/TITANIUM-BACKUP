📱 Termux Backup Manager

---

✨ Features

Feature	Description	
🗄️ Full Backup	Complete snapshot of `home` + `usr` (all packages, configs, dotfiles)	
📦 Selective Backup	Packages list + configs + scripts only (lightweight & fast)	
♻️ Smart Restore	Restore from Latest symlink or choose any previous backup	
🔧 Selective Restore	Re-install packages & merge configs without wiping existing data	
📋 Inventory View	See all backups with size, date & type at a glance	
🗑️ Auto Cleanup	Keep last 3 backups, delete older ones with one key	
⚡ Quick Mode	Silent background backup for cron jobs	
🎨 Modern TUI	Color-coded menu with spinners & progress indicators	

---

🚀 Quick Start

1️⃣ Download & Setup

```bash
# Grant storage access (first time only)
termux-setup-storage

# Download the script
curl -L -o termux-manager.sh https://raw.githubusercontent.com/yourusername/termux-backup-manager/main/termux-manager.sh

# Make it executable
chmod +x termux-manager.sh

# Run it
./termux-manager.sh
```

2️⃣ First Backup

```
┌─────────────────────────────────────────┐
│  Termux Intelligent Backup Manager      │
│                                         │
│  [1] 🗄️  Full Backup      ← Choose this │
│  [2] 📦 Selective Backup                │
│  [3] ♻️  Full Restore                   │
│  ...                                    │
└─────────────────────────────────────────┘
```

---

📖 Usage Guide

🗄️ Full Backup
Backs up everything — all installed packages, configurations, scripts, and dotfiles.

```bash
# From menu: Option 1
# Output: /sdcard/termux-backups/termux-full-YYYYMMDD_HHMMSS.tar.gz
```

> 💡 Pro Tip: The script automatically creates a `LATEST_FULL.tar.gz` symlink so you never have to remember filenames.

---

📦 Selective Backup
Lightweight backup for developers who want to version-control their environment.

What gets backed up	What doesn't	
✅ Installed package list	❌ Package binaries	
✅ `.bashrc`, `.zshrc`, `.profile`	❌ Cache files	
✅ `.termux/`, `.config/`, `.ssh/`	❌ Large downloads	
✅ `~/bin`, `~/scripts`	❌ `~/storage`	

```bash
# From menu: Option 2
# Output: /sdcard/termux-backups/termux-selective-YYYYMMDD_HHMMSS.tar.gz
```

---

♻️ Full Restore
Perfect for: New phone, factory reset, or fresh Termux install.

```bash
# Before restoring:
Settings → Apps → Termux → Clear Data

# Then run script and choose Option 3
```

> ⚠️ Warning: Full restore overwrites all current Termux data. Restart Termux after completion.

---

🔧 Selective Restore
Perfect for: Migrating configs to an existing Termux setup.

```bash
# From menu: Option 4
# What happens:
#   1. Reads package-list.txt from backup
#   2. Re-installs all packages one by one
#   3. Extracts configs into $HOME
```

---

📁 Backup Storage Structure

```
/sdcard/
└── 📂 termux-backups/
    ├── 🗄️  termux-full-20260526_223000.tar.gz      (1.2 GB)
    ├── 🗄️  termux-full-20260602_150045.tar.gz      (1.3 GB)
    ├── 📦 termux-selective-20260526_223500.tar.gz  (15 MB)
    ├── 🔗 LATEST_FULL.tar.gz → termux-full-20260602_150045.tar.gz
    └── 🔗 LATEST_SELECTIVE.tar.gz → termux-selective-20260526_223500.tar.gz
```

---

🎛️ Menu Options

Key	Action	When to Use	
`1`	🗄️ Full Backup	Before any major change	
`2`	📦 Selective Backup	Weekly config snapshot	
`3`	♻️ Full Restore	New device / after reset	
`4`	🔧 Selective Restore	Keep data, restore packages	
`5`	📋 List Backups	Check what's stored	
`6`	🗑️ Delete Old	Free up storage space	
`7`	⚡ Quick Backup	Silent mode for cron	
`0`	❌ Exit	Close the manager	

---

⚙️ Automation (Cron Job)

Set up automatic weekly backups with Termux's cron:

```bash
# Install cron
pkg install cronie

# Edit crontab
crontab -e

# Add this line for every Sunday at 3 AM
0 3 * * 0 /data/data/com.termux/files/home/termux-manager.sh <<< "7" >> /sdcard/termux-cron.log 2>&1
```

---

🛡️ What's Excluded?

To keep backups clean and fast, these are automatically skipped:

Excluded Path	Reason	
`~/storage`	Android storage symlink (infinite loop risk)	
`~/.cache`	Temporary application caches	
`/usr/var/cache/apt/archives`	Downloaded `.deb` packages	
`/usr/tmp`	Temporary system files	

---

🖼️ Preview

```
╔══════════════════════════════════════════════════════╗
║      Termux Intelligent Backup & Restore Manager       ║
║       Backup Location: /sdcard/termux-backups        ║
╚══════════════════════════════════════════════════════╝

  [1] 🗄️  Full Backup (Complete Termux)
  [2] 📦 Selective Backup (Packages + Configs + Scripts)
  [3] ♻️  Full Restore (from Latest or Choose)
  [4] 🔧 Selective Restore (Packages + Configs only)
  [5] 📋 List All Backups
  [6] 🗑️  Delete Old Backups
  [7] ⚡ Quick Backup (Silent Full Backup)
  [0] ❌ Exit

  👉 আপনার অপশন নির্বাচন করুন [0-7]:
```

---

📝 Requirements

- Android 7.0+ with Termux installed
- Storage Permission (`termux-setup-storage`)
- Bash (pre-installed in Termux)

---

🤝 Contributing

Found a bug or want a new feature?

1. 🍴 Fork the repo
2. 🌿 Create your branch (`git checkout -b feature/amazing`)
3. 💾 Commit changes (`git commit -m 'Add amazing feature'`)
4. 📤 Push to branch (`git push origin feature/amazing`)
5. 🔁 Open a Pull Request

---

📜 License

```
MIT License
Copyright (c) 2026 Your Name
```
