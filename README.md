# HelloID-Conn-SA-Full-AD-Youforce-Update-UPN-Email

| :information_source: Information |
| :------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as credentials and API access. You may need to sign an agreement with Visma RAET/Youforce before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

_HelloID-Conn-SA-Full-AD-Youforce-Update-UPN-Email_ is a delegated form designed for use with HelloID Service Automation (SA). It can be imported into HelloID and customized according to your requirements.

This HelloID Service Automation Delegated Form provides updates for user principal name and email on an AD user account and Youforce employee. By using this delegated form, you can manage the following:

1. Search and select the target AD user account
2. Display basic AD user account attributes of the selected target user
3. Enter new values for the following AD user account attributes: UserPrincipalName and EmailAddress
4. Validate the entered UserPrincipalName and EmailAddress values
5. Update AD user account [UserPrincipalName and EmailAddress] and Youforce employee [EmAd] attribute with new values
6. Writing back [EmAd] in Youforce will be skipped if the employee is not found in Youforce

## Getting started

### Requirements

- **Active Directory Access:**<br>
  Access to an Active Directory environment with appropriate permissions to query and modify user account attributes.
  
- **Youforce API Credentials:**<br>
  - Authorized Visma Developers account to request and receive API credentials in the [Visma Developer portal](https://oauth.developers.visma.com). Please follow the [Visma documentation on how to register the App and grant access to client data](https://community.visma.com/t5/Kennisbank-Youforce-API/Visma-Developer-portal-een-account-aanmaken-applicatie/ta-p/527059).
  - ClientID, ClientSecret and tenantID to authenticate with the IAM API of Raet YOuforcee.
  
- **HelloID Configuration:**<br>
  - HelloID agent with access to both Active Directory and the Youforce API.
  - Dependent account data in HelloID. The provisioned system should be dependent on this Users Target Connector and the values needed to be written back should be stored on the account data (e.g UserPrincipalName).
  
- **Youforce Configuration:**<br>
  - Youforce must be configured to automatically process imports. The mutations are submitted to Youforce through the API using the fixed process code IDA. The application administrator must tick the green checkboxes for process code IDA in the configuration import process screen.

### Connection settings

The following user-defined variables are used by the connector:

| Setting | Description | Mandatory |
| --- | --- | --- |
| ADusersSearchOU | Array of Active Directory OUs for scoping AD user accounts in the search result of this form (e.g., `[{ "OU": "OU=Disabled Users,OU=HelloID Training,DC=veeken,DC=local"},{ "OU": "OU=Users,OU=HelloID Training,DC=veeken,DC=local"}]`) | Yes |
| YouforceClientid | The Youforce ClientID to connect to the webservice (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) | Yes |
| YouforceClientsecret | The Youforce Client Secret to connect to the webservice (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) | Yes |
| Youforcetenantid | The Youforce Tenant ID to identify the tenant on the webservice (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) | Yes |

## Remarks

### Supported Fields
- Currently, only the UserPrincipalName and EmailAddress fields can be updated on the AD user account and the EmAd field on the Youforce employee. No other fields are currently supported.
- When the value in Raet Youforce equals the value in HelloID, the action will be skipped (no update will take place).

### Asynchronous Processing
- The Youforce endpoint operates asynchronously. The data is first stored and internally verified before being submitted to BO4. A ticketId is returned to track the processing in the API. The ticket ID must be used to check the status of the API call.
- Within the API, various validation checks are performed:
  - Email address format validation (e.g., aaaa@bbbb.xxx)
  - Phone number validation (alphanumeric values are not supported, but formats like "035-1234567" are supported)

### ProxyAddresses Management
- When updating the EmailAddress in AD, the old primary 'SMTP:' entry will be replaced by an alias 'smtp:' to maintain proper proxy address management.

## Development resources

### API endpoints

The following Youforce API endpoints and Active Directory queries are used by the connector:

| Endpoint/Resource | Description |
| --- | --- |
| AD User Query | Query Active Directory for user accounts based on OU scope |
| Youforce IAM API | Update employee attributes through the Youforce IAM API using process code IDA |

### API documentation

- [Visma Youforce IAM API Documentation](https://oauth.developers.visma.com)
- [Visma Developer Portal](https://community.visma.com/t5/Kennisbank-Youforce-API/Visma-Developer-portal-een-account-aanmaken-applicatie/ta-p/527059)
- [HelloID Service Automation Documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html)

### Implementation resources

The following resources are included with this connector:

#### All-in-one PowerShell Setup Script
The PowerShell script "createform.ps1" contains a complete PowerShell script using the HelloID API to create the complete form including user-defined variables, tasks, and data sources.

**Note:** This script assumes none of the required resources exist within HelloID. The script does not contain versioning or source control. Please follow the documentation steps on [HelloID Docs](https://docs.helloid.com/en/github-resources/service-automation-github-resources.html) to set up and run the All-in-one PowerShell Script in your own environment.

#### PowerShell Data Sources
- **AD-Youforce-account-update-upn-email-lookup-user-generate-table**: Runs an Active Directory query to search for matching AD user accounts using the ADusersSearchOU variable. Returns current UserPrincipalName/EmailAddress values split into prefix and suffix.
- **AD-Youforce-account-update-upn-email-table-user-details**: Runs an Active Directory query to retrieve an extended list of user attributes for the selected AD user account.
- **AD-Youforce-account-update-upn-email-validation**: Validates the uniqueness of new UserPrincipalName and EmailAddress values, including ProxyAddresses, and returns "Valid" or "Invalid" status.

#### Delegated Form Task
- **AD Youforce Account - Update UPN - Email**: Updates two systems:
  - On the AD user account: Updates UserPrincipalName, EmailAddress, and ProxyAddresses (old primary 'SMTP:' replaced by alias 'smtp:')
  - On the Youforce employee: Updates the EmAd attribute

#### Extending the Form
It is possible to add other systems to update the UserPrincipalName and EmailAddress by adding them in the task script. It is also possible to send an [email notification](https://docs.helloid.com/en/service-automation/products/product-tasks.html#email-sends-in-powershell-product-tasks) through the task script.

## Getting help

> :bulb: **Tip:**  
> _For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
