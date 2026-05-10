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

---

## 🚀 Quick Start

### Option 1: Interactive Menu (Recommended for Home Users)
```powershell
# run
powershell -ExecutionPolicy Bypass -NoProfile -Command "irm https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/OneDrive-Hybrid-Toolkit.ps1 | iex"

powershell -ExecutionPolicy Bypass -NoProfile -Command "irm https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/eventIDs.ps1 | iex"

powershell -ExecutionPolicy Bypass -NoProfile -Command "iwr https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/Network_analyze.ps1 -OutFile $env:TEMP\Network_analyze.ps1; & $env:TEMP\Network_analyze.ps1"
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


# Windows Event Export Toolkit

Comprehensive PowerShell tool for exporting:

- 🔐 Biometric & Personal Vault events  
- ☁️ OneDrive sync conflicts & error codes  
- 🛡️ Security audit events  
- 💻 System-level service & driver events  
- 📂 Internal OneDrive log analysis  

Designed for deep diagnostics, incident analysis, and troubleshooting OneDrive / Windows authentication issues.

---

# Windows Event & OneDrive Diagnostic Export Tool

A comprehensive PowerShell diagnostic script that exports:

- 🔐 Biometric & Personal Vault events  
- ☁️ OneDrive sync conflicts & error codes  
- 🛡️ Security audit events  
- 💻 System service & driver events  
- 📂 Internal OneDrive log analysis  

Designed for troubleshooting, audit analysis, and deep diagnostics of Windows authentication and OneDrive issues.

---

