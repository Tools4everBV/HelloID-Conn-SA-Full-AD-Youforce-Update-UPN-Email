# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.0.0] - 2026-04-17

This release introduces significant improvements and updates to the AD and Youforce Account Update UPN and Email connector.

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

- Initial release of the AD Beaufort Account - Update UPN - Email delegated form
- PowerShell data source for AD user account lookup and search functionality
- PowerShell data source for retrieving extended AD user account attributes
- PowerShell data source for validating new UserPrincipalName and EmailAddress values
- Delegated form task for updating AD user account attributes (UserPrincipalName, EmailAddress, ProxyAddresses)
- Delegated form task for updating Beaufort employee attributes (EmAd)
- Support for multiple Active Directory OUs via user-defined variables
- Integration with Beaufort IAM API for employee data updates
- Validation of email address format and phone number format
- All-in-one PowerShell setup script for easy deployment
- Configuration support for HelloID user-defined variables

### Changed

### Deprecated

### Removed

---

