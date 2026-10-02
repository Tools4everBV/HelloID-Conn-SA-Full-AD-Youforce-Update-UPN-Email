# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.2] - 2026-10-02

### Fixed

- Fixed typo in the task

## [2.0.1] - 2026-08-04

### Fixed

- Validation regex was incorrect [#2](https://github.com/Tools4everBV/HelloID-Conn-SA-Full-AD-Youforce-Update-UPN-Email/issues/2)
- ProxyAddresses are not included in the form output [#3](https://github.com/Tools4everBV/HelloID-Conn-SA-Full-AD-Youforce-Update-UPN-Email/issues/3)

## [2.0.0] - 2026-04-17

This release introduces improvements and updates to the AD and Youforce Account Update UPN and Email connector.

### Added

- Enhanced validation for UserPrincipalName and EmailAddress fields
- Improved error handling and logging
- Support for ProxyAddresses management
- Advanced filtering capabilities for AD user searches

### Changed

- Changed AD lookup filtering:
    Search by Name, DisplayName, UserPrincipalName, and mail
    Use semicolon-separated OU values in ADusersSearchOU
- Updated PowerShell data sources for improved performance
- Enhanced AD account update logic to handle complex scenarios
- Improved Youforce employee attribute synchronization
- Better handling of email address format validation

### Deprecated

### Removed

---

## [1.0.0] - 2023-10-24

This is the first official release of the HelloID Service Automation Delegated Form for updating user principal name and email on AD user accounts and Beaufort employees.

### Added

### Changed

### Deprecated

### Removed

---

