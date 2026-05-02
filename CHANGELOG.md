# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-05-02
### Added
- Hybrid release: Merges consumer safety features with professional self-update capabilities
- Interactive menu UI for non-technical users
- `-RemoveMyFiles` with explicit `YES` confirmation guard
- `-PostRebootCleanup` SYSTEM task for locked files
- `-BlockReinstall` policy management
- `-CheckForUpdate` and `-UpdateSelf` via GitHub/PowerShell Gallery
- Dual logging: console colors + transcript file

### Changed
- Replaced regex string parsing with PS 5.1-safe `.StartsWith()`/`.IndexOf()` methods
- Simplified parameter validation for parser compatibility
- Consolidated error handling with structured `try/catch`

### Removed
- Complex `[ValidateSet()]` metadata that caused PS 5.1 parser errors
- Redundant verbose logging that cluttered output

## [1.0.0] - 2026-04-15
### Added
- Initial release based on community OneDrive removal scripts
- Basic CLI switches: `-Remove`, `-DeepClean`, `-NoPrompt`
- AppX package removal
- Registry cleanup for common OneDrive keys