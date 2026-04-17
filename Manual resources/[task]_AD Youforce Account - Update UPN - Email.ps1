# variables configured in form:
$user = $form.gridUsers
$blnmail = [System.Convert]::ToBoolean($form.blnMail)
$blnupn = [System.Convert]::ToBoolean($form.blnUPN)
$blnidentity = $false
$newMailAddress = $form.newMail
$newUserPrincipalName = $form.newUPN
$Script:AuthenticationUri = "https://connect.visma.com/connect/token"
$Script:BaseUri = "https://api.youforce.com"
$clientId = $BeaufortClientid
$clientSecret = $BeaufortClientsecret
$TenantId = $Beauforttenantid

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

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
        Set-ADUser -Identity $user.ObjectGuid -userprincipalname $newUserPrincipalName 

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
        Message           = "Failed to update AD user [$($user.userPrincipalName)] attributes [userPrincipalName] from [$($user.userPrincipalName)] to [$newUserPrincipalName], [emailaddress] from [$($user.mail)] to [$newMailAddress]" # required (free format text) 
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

#region Beaufort contact details
try {

    $accessTokenValid = Confirm-AccessTokenIsValid

    if ($true -ne $accessTokenValid) {
        New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
    }

    $actionMessage = "retrieving correlated account from Youforce API for person [$($user.EmployeeID)]"
    $splatWebRequest = @{
        Uri             = "$youforceBaseUrl/iam/v1.0/persons/$($user.EmployeeID)"
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
            Uri             = "$youforceBaseUrl/iam/v1.0/ContactDetails/$($correlatedAccount.personCode)"
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
#endregion Beaufort contact details

#region Beaufort Identity
if ($blnidentity -eq $true) {
    try {

        $accessTokenValid = Confirm-AccessTokenIsValid

        if ($true -ne $accessTokenValid) {
            New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId
        }

        $actionMessage = "retrieving correlated account from Youforce API for user [$($user.EmployeeID)]"
        $splatWebRequest = @{
            Uri             = "$($Script:BaseUrl)/iam/v1.0/users(employeeId=$($user.EmployeeID))"
            Headers         = $Script:AuthenticationHeaders
            Method          = 'GET'
            ContentType     = "application/json"
            UseBasicParsing = $true
        }
        $correlatedAccount = Invoke-RestMethod @splatWebRequest

        if ($null -eq $correlatedAccount.id) {
            throw 'No user found in Youforce'
        }

        $actionMessage = "checking and updating business email attribute in Youforce for user [$($correlatedAccount.personCode)]"

        if ($null -ne $correlatedAccount.id) {
            if ([string]$correlatedAccount.identityId -ne $newUserPrincipalName -and $null -ne $newUserPrincipalName) {
                $updateAccount = [PSCustomObject]@{
                    id = $newUserPrincipalName
                }

                $body = ($updateAccount | ConvertTo-Json -Depth 10) 

                $splatWebRequest = @{
                    Uri             = "$($Script:BaseUrl)/iam/v1.0/users(employeeId=$($user.EmployeeID))/identity"
                    Headers         = $Script:AuthenticationHeaders
                    Method          = 'PATCH'
                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType     = "application/json;charset=utf-8"
                    UseBasicParsing = $true
                }
                $null = Invoke-RestMethod @splatWebRequest

                $Log = @{
                    Action            = "UpdateAccount"
                    System            = "Youforce"
                    Message           = "Successfully updated Youforce Identity [$($user.EmployeeID)] attributes [identity] from [$($correlatedAccount.identityId)] to [$($newUserPrincipalName)]"
                    IsError           = $false
                    TargetDisplayName = $user.userPrincipalName # optional (free format text) 
                    TargetIdentifier  = $user.ObjectGuid # optional (free format text) 
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
            else {
                $Log = @{
                    Action            = "UpdateAccount"
                    System            = "Youforce"
                    Message           = "Successfully checked Youforce Identity [$($user.EmployeeID)] attributes [identity] [$($correlatedAccount.identityId)], no changes needed"
                    IsError           = $false
                    TargetDisplayName = $user.userPrincipalName # optional (free format text) 
                    TargetIdentifier  = $user.ObjectGuid # optional (free format text) 
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
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
            TargetIdentifier  = $user.ObjectGuid # optional (free format text) 
        }
        Write-Information -Tags "Audit" -MessageData $log
        Write-Warning $warningMessage
        Write-Error $auditMessage
    }
}
#endregion Beaufort Identity

