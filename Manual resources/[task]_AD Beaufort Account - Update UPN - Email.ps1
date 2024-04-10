#######################################################################
# Template: RHo HelloID SA Delegated form task
# Name:     AD-account-update-upn-email
# Date:     24-10-2023
#######################################################################

# For basic information about delegated form tasks see:
# https://docs.helloid.com/en/service-automation/delegated-forms/delegated-form-powershell-scripts/add-a-powershell-script-to-a-delegated-form.html

# Service automation variables:
# https://docs.helloid.com/en/service-automation/service-automation-variables/service-automation-variable-reference.html
$dryRun = $false
#region init
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# global variables (Automation --> Variable libary):
# $globalVar = $globalVarName

# variables configured in form:
$currentEmail =#$form.gridUsers.EmailAddress
$currentUPN = $form.gridUsers.UserPrincipalName
$emailPrefix =  $form.emailPrefix
$emailSuffixCurrent = $form.emailSuffixCurrent
$emailSuffixNew = $form.emailSuffixNew
$upnPrefix = $form.upnPrefix
$upnSuffixCurrent = $form.upnSuffixCurrent
$upnSuffixNew = $form.upnSuffixNew
$employeeID = $form.gridUsers.employeeID
$displayName = $form.gridUsers.displayName
$upnEmailEqual = $form.upnEmailEqual

$correlationProperty = "personCode"
$correlationValue = $employeeID

#endregion init

#region global

if ([string]::IsNullOrEmpty($upnSuffixNew)) {
    $newUPN = $upnPrefix + $upnSuffixCurrent
}
else {
    $newUPN = $upnPrefix + $upnSuffixNew
}

if ($upnEmailEqual -eq "True") {
    $newEmail = $newUPN
}
else {
    if ([string]::IsNullOrEmpty($emailSuffixNew)) {
        $newEmail = $emailPrefix + $emailSuffixCurrent
    }
    else {
        $newEmail = $emailPrefix + $emailSuffixNew
    }
}

#endregion global

#region AD
# Search user
try {
    $properties = @('SID', 'ObjectGuid', 'UserPrincipalName', 'SamAccountName', 'Mail', 'ProxyAddresses', 'EmployeeId')
    $adUser = Get-ADuser -Filter { UserPrincipalName -eq $currentUPN } -Properties $properties
    Write-Information "Found AD user [$currentUPN]"
    
}
catch {
    Write-Error "Could not find AD user [$currentUPN]. Error: $($_.Exception.Message)"    
}

# Set UPN
try {

    Set-ADUser -Identity $adUser -userprincipalname $newUPN
    
    Write-Information "Finished update attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]"
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
        System            = "ActiveDirectory" # optional (free format text) 
        Message           = "Successfully updated attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $adUser.name # optional (free format text) 
        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log    
}
catch {
    Write-Error "Could not update attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]. Error: $($_.Exception.Message)"
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
        System            = "ActiveDirectory" # optional (free format text) 
        Message           = "Failed to update attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]" # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $adUser.name # optional (free format text) 
        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log      
}

# Set EmailAdress and update proxyAddresses
try {
    $proxyAddresses = @()
    foreach ($address in $adUSer.ProxyAddresses) {
        if ($address.StartsWith('SMTP:')) {
            $address = $address -replace 'SMTP:', 'smtp:'
        }
        if ($address -eq "smtp:" + $newEmail) {
        }
        else {
            $proxyAddresses += $address
        }
    }

    $newPrimary = 'SMTP:' + $newEmail
    $proxyAddresses += $newPrimary

    Set-ADUser -Identity $adUSer -emailaddress $newEmail -Replace @{proxyAddresses = $proxyAddresses }

    Write-Information "Finished update attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]"
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
        System            = "ActiveDirectory" # optional (free format text) 
        Message           = "Successfully updated attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $adUser.name # optional (free format text) 
        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log        
}
catch {
    Write-Error "Could not update attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]. Error: $($_.Exception.Message)"
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
        System            = "ActiveDirectory" # optional (free format text) 
        Message           = "Failed to update attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]" # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $adUser.name # optional (free format text) 
        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log     
}
#endregion AD

#region Beaufort
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [HelloID.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}

function New-RaetSession {
    [CmdletBinding()]
    param (
        [Alias("Param1")] 
        [parameter(Mandatory = $true)]  
        [string]      
        $ClientId,

        [Alias("Param2")] 
        [parameter(Mandatory = $true)]  
        [string]
        $ClientSecret,

        [Alias("Param3")] 
        [parameter(Mandatory = $false)]  
        [string]
        $TenantId
    )

    #Check if the current token is still valid
    $accessTokenValid = Confirm-AccessTokenIsValid
    if ($true -eq $accessTokenValid) {
        return
    }

    try {
        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

        $authorisationBody = @{
            'grant_type'    = "client_credentials"
            'client_id'     = $ClientId
            'client_secret' = $ClientSecret
            'tenant_id'     = $TenantId
        }        
        $splatAccessTokenParams = @{
            Uri             = $Script:AuthenticationUri
            Headers         = @{'Cache-Control' = "no-cache" }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorisationBody
            UseBasicParsing = $true
        }

        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false
        if ($null -eq $result.access_token) {
            throw $result
        }

        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)

        $Script:AuthenticationHeaders = @{
            'Authorization' = "Bearer $($result.access_token)"
            'Accept'        = "application/json"
        }

        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error creating Access Token at uri ''$($splatAccessTokenParams.Uri)'. Please check credentials. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })     
    }
}




function Confirm-AccessTokenIsValid {
    if ($null -ne $Script:expirationTimeAccessToken) {
        if ((Get-Date) -le $Script:expirationTimeAccessToken) {
            return $true
        }
    }
    return $false
}
# Used to connect to Beaufort API endpoints
$Script:AuthenticationUri = "https://connect.visma.com/connect/token"
$Script:BaseUri = "https://api.youforce.com"

$clientId = $BeaufortClientid
$clientSecret = $BeaufortClientsecret
$TenantId = $Beauforttenantid


#Change mapping here
$account = [PSCustomObject]@{
    emailAddress = $newUPN
    #phoneNumber  = $phoneFixed
}

$filterfieldid = "Medewerker"
$filtervalue = $employeeID # Has to match the Beaufort value of the specified filter field ($filterfieldid)

# Get current account and verify if the action should be either [updated and correlated] or just [correlated]
try {

    $accessTokenValid = Confirm-AccessTokenIsValid

    if ($true -ne $accessTokenValid) {
        New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
    }

    Write-Verbose "Querying Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"

    $splatWebRequest = @{
        Uri             = "$($Script:BaseUri)/iam/v1.0/persons/$($correlationValue)"
        Headers         = $Script:AuthenticationHeaders
        Method          = 'GET'
        ContentType     = "application/json"
        UseBasicParsing = $true
    }
    $currentAccount = $null
    $currentAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false


    if ($null -ne $currentAccount.id) {
        Write-Verbose "Successfully found Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"
    } 
    else {
        throw "No employee found in Raet Beaufort with $($correlationProperty) '$($correlationValue)'"
    }


    # Get value of current Business Email Address
    if ($null -ne $currentAccount.emailAddresses) {
        $businessEmailAddress = $currentAccount.emailAddresses | Where-Object { $_.type -eq "Business" }
        $businessEmailAddressValue = $businessEmailAddress.address
    }

    # Retrieve current account data for properties to be updated
    $previousAccount = [PSCustomObject]@{
        'emailAddress' = $businessEmailAddressValue
        #'phoneNumber'  = $businessPhoneNumberValue
    }
    
    $splatCompareProperties = @{
        ReferenceObject  = @($previousAccount.PSObject.Properties)
        DifferenceObject = @($account.PSObject.Properties)
    }
    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where( { $_.SideIndicator -eq '=>' })
    
    if ($propertiesChanged) {
        Write-Verbose "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"
    
        foreach ($changedProperty in $propertiesChanged) {
            Write-Verbose "Updating field $($changedProperty.name) '$($previousAccount.($changedProperty.name))' with new value '$($account.($changedProperty.name))'"
        }

        $updateAction = 'Update'
    }
    else {
        $updateAction = 'NoChanges'
    }

    switch ($updateAction) {
        'Update' {

            try {
                $body = ($account | ConvertTo-Json -Depth 10)
                $splatWebRequest = @{
                    Uri             = "$($Script:BaseUri)/iam/v1.0/ContactDetails/$($correlationValue)"
                    Headers         = $Script:AuthenticationHeaders
                    Method          = 'POST'
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }

                Write-Verbose "Updating Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'. Account object: $($account | ConvertTo-Json -Depth 10)"
                                
                if (-not($dryRun -eq $true)) {
                    
                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    $auditLogs.Add([PSCustomObject]@{
                            # Action  = "" # Optional
                            Message = "Successfully updated Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: Would update Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'. Account object: $($account | ConvertTo-Json -Depth 10)"
                }

                break
            }
            catch {
                $ex = $PSItem
                $errorMessage = Get-ErrorMessage -ErrorObject $ex

                Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
                    
                $Log = @{
                    Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
                    System            = "Beaufort Employee" # optional (free format text) 
                    Message           = "Successfully updated attribute [EmAd] of Beaufort emplyee [$employeeID] from [$($currentAccount.Email_werk)] to [$newEmail]" # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $displayName # optional (free format text) 
                    TargetIdentifier  = $([string]$employeeID) # optional (free format text) 
                }
            }
        }
        'NoChanges' {

            Write-Verbose "No changes to Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"
        
            if (-not($dryRun -eq $true)) {

                $Log = @{
                    Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
                    System            = "Beaufort Employee" # optional (free format text) 
                    Message           = "Skipped update attribute [EmAd] of Beaufort employee [$employeeID] to [$newEmail]: No Beaufort employee found with $($filterfieldid) $($filtervalue)" # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $displayName # optional (free format text) 
                    TargetIdentifier  = $([string]$employeeID) # optional (free format text)
                }
            }
            else {
                Write-Warning "DryRun: No changes to Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"
            }                  

            break
        }
    }
}

catch {

    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = Resolve-BeaufortErrorMessage -ErrorObject $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    if ($auditErrorMessage -Like "No Beaufort employee found with $($filterfieldid) $($filtervalue)") {
        Write-Error "Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: No Beaufort employee found with $($filterfieldid) $($filtervalue)"
        Write-Information "Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: No Beaufort employee found with $($filterfieldid) $($filtervalue)"
        $Log = @{
            Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
            System            = "Beaufort Employee" # optional (free format text) 
            Message           = "Failed to update attribute [Mail] of Beaufort employee [$employeeId] to [$businessEmailAddressValue]: No Beaufort employee found with $($filterfieldid) $($filtervalue)" # required (free format text) 
            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $displayName # optional (free format text) 
            TargetIdentifier  = $([string]$employeeID) # optional (free format text) 
        }
        #send result back  
        Write-Information -Tags "Audit" -MessageData $log 
    }
    else {
        Write-Error "Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: Error querying Beaufort employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
        Write-Information "Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: Error querying Beaufort employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage"
        $Log = @{
            Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
            System            = "Beaufort Employee" # optional (free format text) 
            Message           = "Failed to update attribute [Mail] of Beaufort employee [$employeeId] to $businessEmailAddressValue]: Error querying Beaufort employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage" # required (free format text) 
            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $displayName # optional (free format text) 
            TargetIdentifier  = $([string]$employeeID) # optional (free format text) 
        }
        #send result back  
        Write-Information -Tags "Audit" -MessageData $log  
    }
}

# Update Beaufort Employee
try {
    Write-Information "Start updating Beaufort employee [$($currentAccount.Medewerker)]"
    switch ($updateAction) {
        'Update' {
            try {
                $body = ($account | ConvertTo-Json -Depth 10)
                $splatWebRequest = @{
                    Uri             = "$($Script:BaseUri)/iam/v1.0/ContactDetails/$($correlationValue)"
                    Headers         = $Script:AuthenticationHeaders
                    Method          = 'POST'
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }

                Write-Verbose "Updating Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'. Account object: $($account | ConvertTo-Json -Depth 10)"
                                
                if (-not($dryRun -eq $true)) {
                    
                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false

                    $Log = @{
                        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
                        System            = "Beaufort Employee" # optional (free format text) 
                        Message           = "Successfully updated attribute [EmAd] of Beaufort emplyee [$employeeID] from [$($currentAccount.Email_werk)] to [$newEmail]" # required (free format text) 
                        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                        TargetDisplayName = $displayName # optional (free format text) 
                        TargetIdentifier  = $([string]$employeeID) # optional (free format text) 
                    }
                }
                else {
                    Write-Warning "DryRun: Would update Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'. Account object: $($account | ConvertTo-Json -Depth 10)"
                }

                break
            }
            catch {
                $ex = $PSItem
                $errorMessage = Get-ErrorMessage -ErrorObject $ex
                        
                Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"
                    
                $auditLogs.Add([PSCustomObject]@{
                        # Action  = "" # Optional
                        Message = "Error updating Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'. Error Message: $($errorMessage.AuditErrorMessage) Account object: $($account | ConvertTo-Json -Depth 10)"
                        IsError = $true
                    })
            }
        }
        'NoChanges' {
            Write-Verbose "No changes to Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"
        
            if (-not($dryRun -eq $true)) {
                $Log = @{
                    Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
                    System            = "Beaufort Employee" # optional (free format text) 
                    Message           = "Successfully checked attribute [EmAd] of Beaufort emplyee [$employeeID] from [$($currentAccount.Email_werk)] to [$newEmail], no changes needed" # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $displayName # optional (free format text) 
                    TargetIdentifier  = $([string]$employeeID) # optional (free format text) 
                }
            }
            else {
                Write-Warning "DryRun: No changes to Raet Beaufort employee with $($correlationProperty) '$($correlationValue)'"
            }                  

            break
        }
    }

    # Set aRef object for use in futher actions
    $aRef = $currentAccount.personCode

    # Define ExportData with account fields and correlation property 
    $exportData = $account.PsObject.Copy()
    $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force

    break
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = Resolve-BeaufortErrorMessage -ErrorObject $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    $ex = $PSItem
    $verboseErrorMessage = $ex
    
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    Write-Error "Error updating Beaufort employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage"
    Write-Information "Error updating Beaufort employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage"
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
        System            = "Beaufort Employee" # optional (free format text) 
        Message           = "Error updating Beaufort employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage" # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $displayName # optional (free format text) 
        TargetIdentifier  = $([string]$employeeID) # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log 
}
#endregion Beaufort
