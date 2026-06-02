Welcome! This toolkit is a simple, safe, and automated way to manage OneDrive on your computer. Whether you want to completely remove OneDrive, fix syncing errors, or restore your folders, this tool does the heavy lifting for you.

# OneDrive-Hybrid-Toolkit
PowerShell toolkit to safely remove/reinstall Microsoft OneDrive
# OneDrive Hybrid Toolkit 🧹

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/OneDriveHybridToolkit?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/OneDriveHybridToolkit)
[![GitHub Release](https://img.shields.io/github/v/release/singhj775/OneDrive-Hybrid-Toolkit)](https://github.com/singhj775/OneDrive-Hybrid-Toolkit/releases)
[![License](https://img.shields.io/github/license/singhj775/OneDrive-Hybrid-Toolkit)](LICENSE)

A production-ready PowerShell toolkit to **safely remove or reinstall Microsoft OneDrive** on Windows 10/11. Combines consumer-friendly safety features with professional IT deployment capabilities.

> ✅ **Safe by default**: Never deletes your personal files without explicit confirmation  
> ✅ **PowerShell 5.1 compatible**: Runs on all default Windows installations  
> ✅ **Self-updating**: Check for updates via `-CheckForUpdate` or `-UpdateSelf`  
> ✅ **Dual interface**: Interactive menu for beginners, CLI switches for automation

> 🛡️ Safe by Default: This tool will never delete your files stored in the cloud. It only affects the OneDrive application and files on this specific computer. Your personal files are kept safe unless you explicitly choose the "Delete My Files" option.


---

## 🚀 Quick Start

### Option 1: Interactive Menu (Recommended for Home Users)
```powershell
# run
powershell -ExecutionPolicy Bypass -NoProfile -Command "irm https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/OneDrive-Hybrid-Toolkit.ps1 | iex"

powershell -ExecutionPolicy Bypass -NoProfile -Command "irm https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/eventIDs.ps1 | iex"

powershell -ExecutionPolicy Bypass -NoProfile -Command "iwr https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/Network_analyze.ps1 -OutFile $env:TEMP\Network_analyze.ps1; & $env:TEMP\Network_analyze.ps1"

powershell -ExecutionPolicy Bypass -NoProfile -Command "iwr https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/crosslinked_extension_fix.ps1 -OutFile $env:TEMP\crosslinked_extension_fix.ps1; & $env:TEMP\crosslinked_extension_fix.ps1"

```
---

### Option 2: CLI (Recommended for Pro Users)
Command
```
Launch interactive menu
.\OneDrive-Hybrid-Toolkit.ps1

Safe removal (keep files)
.\OneDrive-Hybrid-Toolkit.ps1 -Remove

Deep clean (remove leftovers)
.\OneDrive-Hybrid-Toolkit.ps1 -Remove -DeepClean

Delete personal OneDrive folder ⚠️
.\OneDrive-Hybrid-Toolkit.ps1 -Remove -DeepClean -RemoveMyFiles

Handle locked files after reboot
.\OneDrive-Hybrid-Toolkit.ps1 -Remove -PostRebootCleanup

Prevent auto-reinstall
.\OneDrive-Hybrid-Toolkit.ps1 -Remove -BlockReinstall

Silent automated run
.\OneDrive-Hybrid-Toolkit.ps1 -Remove -DeepClean -NoPrompt

Reinstall OneDrive
.\OneDrive-Hybrid-Toolkit.ps1 -Reinstall

Check script updates
.\OneDrive-Hybrid-Toolkit.ps1 -CheckForUpdate

Self-update from PSGallery
.\OneDrive-Hybrid-Toolkit.ps1 -UpdateSelf

Show current status
.\OneDrive-Hybrid-Toolkit.ps1 -Status
```
🔐 Administrator rights required: The script will auto-relaunch as Admin if needed.


| Option | Feature Name | What it does (Plain English) |
| :--- | :--- | :--- |
| **1** | Remove OneDrive (Safe) | Uninstalls the app but keeps your downloaded files safe. |
| **2** | Remove + Deep Clean | Uninstalls the app and removes hidden leftover settings. |
| **3** | Remove + Delete My Files | ⚠️ **WARNING:** Uninstalls the app AND deletes the local OneDrive folder on this PC. |
| **4** | Reinstall OneDrive | Installs or restores the OneDrive application. |
| **5** | Block Reinstall (Policy) | Stops Windows from automatically reinstalling OneDrive in the background. |
| **6** | ODC CPU Monitor | A live dashboard that restarts OneDrive if it freezes or uses too much memory. |
| **7** | Character Count Checker | Scans for files with names that are too long or have weird characters that break syncing. |
| **8** | New Local User Account | Creates a temporary local administrator account named "test" (for advanced troubleshooting). |
| **9** | Logs Collection | Gathers error logs, analyzes them for common problems, and creates a neat ZIP file for IT support. |
| **10** | Icon Repair | Fixes broken, missing, or blank icons for OneDrive or File Explorer. |
| **11** | Sync Repair | A complete "reset" for OneDrive. Clears cache, fixes network settings, and reinstalls cleanly. |
| **1A** | Real-Time Folder Monitor | Watches your OneDrive folder and prints a message whenever a file is added or changed. |
| **1B** | Restore Default Folders | Fixes your Desktop, Documents, Pictures, etc., if they disappeared after removing OneDrive. |
| **1C** | Junction Remover | Safely moves your Desktop/Documents folders out of OneDrive and back to your local computer. |
| **0** | Exit | Closes the toolkit. |


# Windows Event Export Toolkit

Comprehensive PowerShell tool for exporting:

- 🔐 Biometric & Personal Vault events  
- ☁️ OneDrive sync conflicts & error codes  
- 🛡️ Security audit events  
- 💻 System-level service & driver events  
- 📂 Internal OneDrive log analysis  

Designed for deep diagnostics, incident analysis, and troubleshooting OneDrive / Windows authentication issues.

---


---

# 🌐 OneDrive Network Trace & Fiddler Configuration Tool

A PowerShell menu-driven utility designed to simplify network troubleshooting for Microsoft OneDrive. This tool automates WinHTTP proxy routing, disables HTTP/3 (QUIC) to force readable traffic, and captures simultaneous `netsh` (`.etl`) and Fiddler (`.saz`) network traces.

---

## ⚠️ Prerequisites

Before using this tool, ensure you have the following:
- **Windows OS** (Windows 10 / 11 / Server)
- **Administrator Privileges** (The script will automatically check and exit if not run as Admin)
- **[Fiddler Classic](https://www.telerik.com/fiddler/fiddler-classic)** installed *(Required for Option 4 to export `.saz` files via FiddlerCore)*

---

## 🚀 Quick Start

1. Download the `OneDriveTraceTool.ps1` script to your local machine.
2. Right-click the file and select **Properties**. If there is an "Unblock" checkbox at the bottom, check it and click **Apply**.
3. Open **PowerShell as Administrator**.
4. Navigate to the folder containing the script.
5. Run the script:
   ```powershell
   .\OneDriveTraceTool.ps1


🛠️ Features & Menu Options
[1] Bypass System Proxy and Route to Fiddler
Configures the Windows WinHTTP proxy to route traffic through 127.0.0.1:8888. This ensures that background services (like OneDrive) send their traffic to Fiddler for inspection, bypassing standard IE/Edge proxy settings.
[2] Disable HTTP/3 and QUIC (Force HTTP/1.1/2)
Modifies the Windows Registry to disable EnableAutoHttp3 and force EnableHttp2Tls.
💡 Why? OneDrive heavily utilizes QUIC (UDP port 443), which is encrypted and difficult to decrypt in standard packet captures. Forcing HTTP/2 over TLS allows Fiddler to decrypt and inspect the traffic.
Note: You must restart OneDrive after applying this change.
[3] Revert All Changes
Cleans up the system by:
Resetting the WinHTTP proxy to direct connection.
Removing the HTTP/2 and HTTP/3 registry keys.
Attempting to remove the DO_NOT_TRUST_FiddlerRoot certificate from the Trusted Root Certification Authorities store.
[4] Start Dual Capture (netsh .etl + Fiddler .saz)
The core troubleshooting feature. It performs the following:
Creates an output directory: C:\OneDriveTraces\
Starts a Windows netsh trace (.etl + .cab).
Loads FiddlerCore.dll to start capturing sessions in the background.
Prompts you to reproduce your OneDrive issue (e.g., sync conflicts, Personal Vault unlocks, upload failures).
Stops both captures upon pressing Enter and exports the .saz archive.
[5] Exit
Safely closes the script.

This script modifies system network settings and Windows Registry keys. While it includes a "Revert" function to clean up after itself, it is provided as-is. Always ensure you understand the changes being made to your system before executing administrative scripts. The author is not responsible for any unintended side effects.



## 🛠 What This crosslink extension Script Does

- Scans files
- Detects real file type using TrID
- Suggests correct extension
- Helps fix ransomware-crosslinked extensions

