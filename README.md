# OneDrive-Hybrid-Toolkit
Production-ready PowerShell toolkit to safely remove/reinstall Microsoft OneDrive
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
# Download and run
irm https://github.com/singhj775/OneDrive-Hybrid-Toolkit/raw/main/OneDrive-Hybrid-Toolkit.ps1 -OutFile "$env:TEMP\OneDriveToolkit.ps1"
& "$env:TEMP\OneDriveToolkit.ps1"
