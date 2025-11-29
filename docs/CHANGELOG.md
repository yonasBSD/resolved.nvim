# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- Added URL validation to prevent path traversal attacks
- Made GitHub CLI auth check async with timeout to prevent hanging
- Added buffer validity checks in all async operations

### Fixed

- Fixed race condition in timer cleanup that could cause crashes
- Fixed buffer validity race conditions in async operations
- Fixed multi-line comment position calculation for CRLF line endings
- Fixed setup to validate preconditions before creating resources
- Fixed silent failures in display module - now logs errors

### Added

- Comprehensive configuration validation with helpful error messages
- Error logging for all extmark placement failures
- Health checks for cache and enabled status
- Extensive test coverage (90%+)
- Double initialization guard in setup

### Changed

- GitHub auth check now uses async with 5 second timeout
- Setup now validates all preconditions before creating resources
- Display module now logs errors instead of failing silently
- Improved multi-line comment handling with CRLF normalization
