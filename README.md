# HelloID-Conn-SA-Full-AD-Youforce-Update-UPN-Email

| :information_source: Information |
| :------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

HelloID-Conn-SA-Full-AD-Youforce-Update-UPN-Email is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can update User Principal Name (UPN) and Email attributes in Active Directory and Youforce. The following options are available:

1. Search and select the target Active Directory user account
2. Enter new values for UserPrincipalName and EmailAddress
3. Validate uniqueness of UserPrincipalName and EmailAddress in Active Directory
4. Update UserPrincipalName, EmailAddress, and ProxyAddresses in Active Directory
5. Update business email details in Youforce when a matching employee is found

## Getting started

### Requirements

#### Active Directory setup

Before implementing this connector, make sure the HelloID Agent runs under an account with sufficient rights to update Active Directory user attributes.

Recommended permissions:

- Account Operators rights (or equivalent delegated rights) to update:
  - UserPrincipalName
  - EmailAddress
  - ProxyAddresses

#### Youforce setup

Ensure Youforce is configured with:

- Youforce tenant id
- Youforce client id
- Youforce client secret
- Access to the Youforce IAM API

#### HelloID-specific configuration

Once you have completed the Active Directory and Youforce setup, configure the following HelloID-specific requirements:

- Configure the user-defined variables listed in Connection settings
- Import and configure the delegated form and task scripts

### Connection settings

The following user-defined variables are used by the connector and should be configured in HelloID Service Automation (Automation -> Variable library).

| Variable Name        | Description                                                             | Required |
| -------------------- | ----------------------------------------------------------------------- | -------- |
| ADusersSearchOU      | Array of Active Directory OUs used to scope user search results         | Yes      |
| YouforceClientid     | The Youforce client id used to authenticate to the Youforce IAM API     | Yes      |
| YouforceClientsecret | The Youforce client secret used to authenticate to the Youforce IAM API | Yes      |
| Youforcetenantid     | The Youforce tenant id used during OAuth token retrieval                | Yes      |

## Remarks

### Uniqueness validation

- The form validates uniqueness for UserPrincipalName and EmailAddress before updating.
- Validation checks both direct attributes and ProxyAddresses.
- The selected user itself is excluded from the uniqueness check.

### ProxyAddresses behavior

- When the primary SMTP value changes, the previous primary address (SMTP:) is converted to an alias (smtp:).
- This preserves historical aliases while setting the new primary address.

### Youforce employee matching

- Youforce updates depend on a valid EmployeeID correlation between Active Directory and Youforce.
- If no matching Youforce employee is found, Youforce updates are skipped while Active Directory updates can still proceed.

### Youforce target objects

- Youforce person contact details endpoint is used to update business email.
- Optional identity updates can be handled through the Youforce IAM users identity endpoint.

## Development resources

### Endpoints and operations

The following operations are used by the connector:

| Operation                                                     | Purpose                                                    |
| ------------------------------------------------------------- | ---------------------------------------------------------- |
| Active Directory (Get-ADUser)                                 | Search and retrieve Active Directory users                 |
| Active Directory (Set-ADUser)                                 | Update UserPrincipalName, EmailAddress, and ProxyAddresses |
| https://connect.visma.com/connect/token                       | Retrieve OAuth access token for Youforce                   |
| https://api.youforce.com/iam/v1.0/persons/{EmployeeID}        | Retrieve correlated Youforce person                        |
| https://api.youforce.com/iam/v1.0/ContactDetails/{PersonCode} | Update Youforce business email details                     |

### API and cmdlet documentation

- Active Directory Get-ADUser: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
- Active Directory Set-ADUser: https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser
- Visma Youforce IAM API Documentation: https://oauth.developers.visma.com

## Getting help
> [!TIP]
> _For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/