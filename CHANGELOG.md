# Changelog

## [Unreleased]

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
