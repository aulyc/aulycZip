# Changelog

## [Unreleased]

## [1.2.2] - 2026-08-20

### Changed

- Replace technical update-delivery details in the available-update dialog with a concise, user-facing summary of improvements and fixes

## [1.2.1] - 2026-08-20

### Fixed

- Ignore macOS helper metadata such as `__MACOSX/`, `.DS_Store`, and AppleDouble `._*` during extraction instead of writing it into the result
- Reuse the compact encrypted-archive completion header after extraction so the application icon and “ZIP extracted” title share one consistently sized row, and remove the extra gap between the output directory and file name

## [1.2.0] - 2026-08-20

### Added

- Add an “Extract into a separate folder” option; keep the ZIP-named folder as the default, allow direct extraction beside the ZIP when disabled, and combine destination and password input in one dialog

### Security and compatibility

- Stage direct extraction inside the destination while validating passwords, authentication, and paths, then reject top-level name conflicts without overwriting or leaving partial output

### Interface

- Unify application icons and compact layouts across encryption, extraction, generated-password, and completion dialogs; middle-truncate long paths while preserving file-name endings, and restore the extraction menu icon

## [1.1.0] - 2026-08-19

### Added

- Add on-demand ZIP64 reading and creation while keeping small archives in classic ZIP, with plain and WinZip AES-256 ZIP64 interoperability coverage
- Stream creation and extraction in fixed-size chunks, stage work in temporary files or directories, and commit results atomically only after complete success
- Add cancellable progress panels for creation, extraction, and updates, plus safe atomic replacement after confirmation in the menu-bar save panel

### Security and compatibility

- Tighten declared entry-size, total-output, entry-count, free-space, path-collision, and symbolic-link defenses, and never write encrypted plaintext before authentication succeeds
- Keep extracted files and directories at conservative `0600`/`0700` permissions without restoring execute bits, while user-created ZIP files follow the process `umask`
- Reject multi-volume ZIP, ZipCrypto, and symbolic-link entries explicitly while preserving non-overwriting Finder service output

### Engineering

- Split password and file-name controls, centralize password validation and progress panels, and remove duplicated or production-unused code
- Install 7-Zip in CI for bidirectional and ZIP64 interoperability tests, and add a Release high-entropy streaming benchmark with memory and duration regression limits
- Remove maintainer-specific absolute paths from release scripts and require an explicitly validated central standards checkout

## [1.0.0] - 2026-08-18

### Added

- Build the initial native AppKit menu-bar application for creating WinZip AES-256 encrypted ZIP files and extracting compatible ZIP archives
- Add Finder Services integration with non-overwriting encrypted archive output
- Add authenticated extraction, path traversal and symlink escape protection, entry and output-size limits, and external compatibility fixtures
- Add automatic daily and manual online update checks using GitHub first and Gitee fallback
- Verify Schema v2 update metadata, immutable release provenance, SHA-256, Developer ID, Hardened Runtime, notarization, Gatekeeper, application identity, and arm64 architecture before replacement
- Add exact-tag release, signing, notarization, provenance, central Git publication, dual-mirror publication, and explicit installation commands
