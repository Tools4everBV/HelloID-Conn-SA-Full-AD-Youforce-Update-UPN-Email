# variables configured in form:
$user = $form.gridUsers
$blnmail = [System.Convert]::ToBoolean($form.blnMail)
$blnupn = [System.Convert]::ToBoolean($form.blnUPN)
$blnidentity = $false
$newMailAddress = $form.newMail
$newUserPrincipalName = $form.newUPN
$employeeID = $user.employeeID

# global variables (Automation --> Variable library):
# Outcommented as these are set from Global Variables
# $YouforceTenantId = ''
# $YouforceClientId = ''
# $YouforceClientSecret = ''

$YouforceAuthenticationUri = "https://connect.visma.com/connect/token"
$YouforceBaseUri = "https://api.youforce.com"

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#region global functions
function Resolve-YouforceError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        Write-Output $httpErrorObj
    }
}
#endregion global functionsResolve-HTTPError {

try {
    $actionMessage = "updating AD attributes for user [$($user.userPrincipalName)] with objectguid [$($user.ObjectGuid)]"

    $proxyAddresses = @()
    foreach ($address in $user.ProxyAddresses) {
        if ($address.StartsWith('SMTP:')) {
            $address = $address -replace 'SMTP:', 'smtp:'
        }
        if ($address -eq "smtp:" + $newMailAddress) {
        }
        else {
            $proxyAddresses += $address
        }
    }

    $newPrimary = 'SMTP:' + $newMailAddress
    $proxyAddresses += $newPrimary

    if ($blnupn -eq $true) {
        Set-ADUser -Identity $user.ObjectGuid -UserPrincipalName $newUserPrincipalName 

        $Log = @{
            Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
            System            = "ActiveDirectory" # optional (free format text) 
            Message           = "Successfully updated AD user [$($user.userPrincipalName)] attributes [userPrincipalName] from [$($user.userPrincipalName)] to [$newUserPrincipalName]" # required (free format text) 
            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $user.userPrincipalName # optional (free format text) 
            TargetIdentifier  = $user.ObjectGuid # optional (free format text) 
        }
        #send result back  
        Write-Information -Tags "Audit" -MessageData $log     
    }

    if ($blnmail -eq $true) {
        Set-ADUser -Identity $user.ObjectGuid -emailaddress $newMailAddress -Replace @{proxyAddresses = $proxyAddresses }

        $Log = @{
            Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
            System            = "ActiveDirectory" # optional (free format text) 
            Message           = "Successfully updated AD user [$($user.mail)] attributes [mail] from [$($user.mail)] to [$newMailAddress]" # required (free format text) 
            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $user.userPrincipalName # optional (free format text) 
            TargetIdentifier  = $user.ObjectGuid # optional (free format text) 
        }
        #send result back  
        Write-Information -Tags "Audit" -MessageData $log     
    }
}
catch {
    $ex = $PSItem
    $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"    

    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
        System            = "ActiveDirectory" # optional (free format text) 
        Message           = "Error $($actionMessage). Error Message: $auditMessage" # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $user.userPrincipalName # optional (free format text) 
        TargetIdentifier  = $user.ObjectGuid # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log      
    Write-Warning $warningMessage   
    Write-Error $auditMessage
}
#endregion AD

#region Youforce
if (-not([string]::IsNullOrEmpty($employeeID))) {
    try {
        $actionMessage = "creating new session for Youforce API"
        $authorizationBody = @{
            'grant_type'    = "client_credentials"
            'client_id'     = $YouforceClientId
            'client_secret' = $YouforceClientSecret
            'tenant_id'     = $YouforceTenantId
        }

        $splatAccessTokenParams = @{
            Uri             = $YouforceAuthenticationUri
            Headers         = @{'Cache-Control' = "no-cache" }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorizationBody
            UseBasicParsing = $true
        }
        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false
        if ($null -eq $result.access_token) {
            throw $result
        }

        $headers = @{
            'Authorization' = "Bearer $($result.access_token)"
            'Accept'        = "application/json"
        }
        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $actionMessage = "retrieving correlated account from Youforce API for person [$employeeID]"
        $splatWebRequest = @{
            Uri             = "$YouforceBaseUri/iam/v1.0/persons/$($employeeID)"
            Headers         = $headers
            Method          = 'GET'
            ContentType     = "application/json"
            UseBasicParsing = $true
        }
        $correlatedAccount = Invoke-RestMethod @splatWebRequest

        if ($null -eq $correlatedAccount.id) {
            throw 'No employee found in Youforce'
        }

        $actionMessage = "checking and updating business email attribute in Youforce for person [$($user.EmployeeID)]"
        if ($null -ne $correlatedAccount.emailAddresses) {
            $businessEmailAddress = $correlatedAccount.emailAddresses | Where-Object { $_.type -eq "Business" }
            $businessEmailAddressOld = $businessEmailAddress.address
            if ([string]::IsNullOrEmpty($businessEmailAddressOld)) {
                $businessEmailAddressOld = ''
            }
        }
        else {
            $businessEmailAddressOld = ''
        }

        if ($businessEmailAddressOld -ne $newMailAddress) {
            $body = [PSCustomObject]@{
                'emailAddress' = $newMailAddress
            }
            $body = $body | ConvertTo-Json -Depth 10
            $splatWebRequest = @{
                Uri             = "$YouforceBaseUri/iam/v1.0/ContactDetails/$($correlatedAccount.personCode)"
                Headers         = $headers
                Method          = 'POST'
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = "application/json;charset=utf-8"
                UseBasicParsing = $true
            }
            $null = Invoke-RestMethod @splatWebRequest

            $Log = @{
                Action            = "UpdateAccount"
                System            = "Youforce"
                Message           = "Successfully updated Youforce personCode [$($correlatedAccount.personCode)] attributes [businessmail] from [$businessEmailAddressOld] to [$newMailAddress]"
                IsError           = $false
                TargetDisplayName = $user.userPrincipalName # optional (free format text) 
                TargetIdentifier  = $correlatedAccount.personCode # optional (free format text) 
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        else {
            $Log = @{
                Action            = "UpdateAccount"
                System            = "Youforce"
                Message           = "Successfully checked Youforce person [$($correlatedAccount.personCode)] attributes [businessmail] [$businessEmailAddressOld], no changes needed"
                IsError           = $false
                TargetDisplayName = $user.userPrincipalName # optional (free format text) 
                TargetIdentifier  = $correlatedAccount.personCode # optional (free format text) 
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
    }
    catch {
        $ex = $PSItem
        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-YouforceError -ErrorObject $ex
            $warningMessage = "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        }
        else {
            $warningMessage = "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        }
        $log = @{
            Action            = "UpdateAccount" # optional. ENUM (undefined = default) 
            System            = "Youforce" # optional (free format text) 
            Message           = $auditMessage # required (free format text) 
            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $user.userPrincipalName # optional (free format text) 
            TargetIdentifier  = $correlatedAccount.personCode # optional (free format text) 
        }
        Write-Information -Tags "Audit" -MessageData $log
        Write-Warning $warningMessage
        Write-Error $auditMessage
    }
}
else {
    $Log = @{
        Action            = "UpdateAccount"
        System            = "Youforce"
        Message           = "Skipped update attributes [businessmail] of Youforce person [$($employeeID)]: employeeID is empty"
        IsError           = $false
        TargetDisplayName = $user.displayName
        TargetIdentifier  = $user.ObjectGuid
    }
    Write-Information -Tags "Audit" -MessageData $log
}
#endregion Youforce
