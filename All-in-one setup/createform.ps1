# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Active Directory","User Management") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> ADusersSearchOU
$tmpName = @'
ADusersSearchOU
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}

        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
	Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "AD AFAS Account - Update UPN - Email - Clone ad-afas-account-update-upn-email | AD-AFAS-account-update-upn-email-validation" #>
$tmpPsScript = @'
# variables configured in form:
$user = $datasource.user
$blnmail = [System.Convert]::ToBoolean($datasource.blnMail)
$blnupn = [System.Convert]::ToBoolean($datasource.blnUPN)
$newMailAddress = $datasource.newMail
$newUserPrincipalName = $datasource.newUPN
$searchUpperCaseEmail = $newMailAddress
$searchLowerCaseEmail = $newMailAddress
$searchUpperCaseUPN = $newUserPrincipalName
$searchLowerCaseUPN = $newUserPrincipalName
$outputText = [System.Collections.Generic.List[PSCustomObject]]::new()

# Global variables
$searchOUs = $ADusersSearchOU

# Fixed values
$propertiesToSelect = @(                    
    "SamAccountName",
    "mail",
    "Name",
    "DisplayName",
    "UserPrincipalName",
    "Enabled", 
    "ObjectGuid"
) # Properties to select from Microsoft AD, comma separated

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region lookup
try {
    $actionMessage = "validating new UPN and mail values"

    if ($blnupn -and ([string]::IsNullOrWhiteSpace($newUserPrincipalName) -or ($user.UserPrincipalName -eq $newUserPrincipalName))) {
        Write-information "UPN [$($user.userPrincipalName)]for user [$($user.userPrincipalName)] with objectguid [$($user.ObjectGuid)] has not been changed"
    }
    if ($blnmail -and ([string]::IsNullOrWhiteSpace($newMailAddress) -or ($user.mail -eq $newMailAddress))) {
        Write-information "Mail [$($user.mail)] for user [$($user.mail)] with objectguid [$($user.ObjectGuid)] has not been changed"
    }

    $actionMessage = "checking AD for uniqueness"

    $filter = "(ObjectGuid -ne '$($user.ObjectGuid)')"

    $filterParts = @()

    if ($blnmail -and -not [string]::IsNullOrWhiteSpace($newMailAddress)) {
        $filterParts += "(mail -eq '$newMailAddress' -or ProxyAddresses -eq 'SMTP:$($newMailAddress.ToUpperInvariant())' -or ProxyAddresses -eq 'smtp:$($newMailAddress.ToLowerInvariant())')"
    }

    if ($blnupn -and -not [string]::IsNullOrWhiteSpace($newUserPrincipalName)) {
        $filterParts += "(UserPrincipalName -eq '$newUserPrincipalName' -or ProxyAddresses -eq 'SMTP:$($newUserPrincipalName.ToUpperInvariant())' -or ProxyAddresses -eq 'smtp:$($newUserPrincipalName.ToLowerInvariant())')"
    }

    if ($filterParts.Count -eq 0) {
        # Nothing to validate for uniqueness
        $filter = "(ObjectGuid -ne '$($user.ObjectGuid)')"
        # Optional: skip Get-ADUser and return Valid directly
    }
    else {
        $filter = "(ObjectGuid -ne '$($user.ObjectGuid)') -and (" + ($filterParts -join ' -or ') + ")"
    }

    Write-Information "SearchBase: $searchOUs"
    
    $ous = $searchOUs -split ';'
    $users = foreach ($item in $ous) {
        $getAdUsersSplatParams = @{
            Filter      = $filter
            Properties  = $propertiesToSelect
            SearchBase  = $item
            Verbose     = $false
            ErrorAction = 'Stop'
        }
        Get-AdUser @getAdUsersSplatParams | Select-Object -Property $propertiesToSelect
    }

    #region Sorting user object(s)
    $users = $users | Sort-Object -Property DisplayName
    $resultCount = @($users).Count
    Write-Information "Result count: $resultCount"

    foreach ($user in $users) {
        if ($user.UserPrincipalName -eq $newUserPrincipalName -and $blnupn) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "UPN [$newUserPrincipalName] not unique, found on [$($user.Name)]"
                    IsError  = $true
                    Property = "UPN"
                })
        }
        if ($user.mail -eq $newMailAddress -and $blnmail) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "Email [$newMailAddress] not unique, found on [$($user.Name)]"
                    IsError  = $true
                    Property = "Email"
                })
        }
        elseif (($user.ProxyAddresses -eq "SMTP:$newUserPrincipalName") -or ($record.ProxyAddresses -eq "smtp:$newUserPrincipalName") -and $blnupn) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "ProxyAddress [$newUserPrincipalName] not unique, found on [$($user.Name)]"
                    IsError  = $true
                    Property = "ProxyAddress"
                })
        }
        elseif (($user.ProxyAddresses -eq "SMTP:$newMailAddress") -or ($record.ProxyAddresses -eq "smtp:$newMailAddress") -and $blnmail) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "ProxyAddress [$newMailAddress] not unique, found on [$($user.Name)]"
                    IsError  = $true
                    Property = "ProxyAddress"
                })
        }
    }

    if ($outputText.isError -contains - $true) {
        $outputMessage = "Invalid"
    }
    else {
        $outputMessage = "Valid"
        if ($blnupn) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "UPN [$newUserPrincipalName] unique"
                    IsError  = $false
                    Property = "UPN"
                })
        }
        if ($blnmail) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "Email [$newMailAddress] unique"
                    IsError  = $false
                    Property = "Email"
                })
        }
    }

    foreach ($text in $outputText) {
        $outputMessage += " | " + $($text.Message)
    }

    $returnObject = @{
        text              = $outputMessage
        userPrincipalName = $newUserPrincipalName
        emailAddress      = $newMailAddress
    }
    Write-Output $returnObject  
}
catch {
    $ex = $PSItem
    Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    Write-Error "Error $($actionMessage). Error: $($ex.Exception.Message)"
}
#endregion lookup
'@ 
$tmpModel = @'
[{"key":"userPrincipalName","type":0},{"key":"text","type":0},{"key":"emailAddress","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"newUPN","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"newMail","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"blnMail","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"blnUPN","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"user","type":0,"options":0}]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
AD AFAS Account - Update UPN - Email - Clone ad-afas-account-update-upn-email | AD-AFAS-account-update-upn-email-validation
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "AD AFAS Account - Update UPN - Email - Clone ad-afas-account-update-upn-email | AD-AFAS-account-update-upn-email-validation" #>

<# Begin: DataSource "AD AFAS Account - Update UPN - Email - Clone ad-afas-account-update-upn-email | AD-Get-Active-Users-DisplayName-Mail-Name-UserprincipalName" #>
$tmpPsScript = @'
# Variables configured in form
$searchValue = $dataSource.searchUser
$searchQuery = "*$searchValue*"

If($searchValue -eq '*'){
    $filter = '*'
} else {
$filter = "Name -like '$searchQuery' -or DisplayName -like '$searchQuery' -or userPrincipalName -like '$searchQuery' -or mail -like '$searchQuery'"
}

# Global variables
$searchOUs = $AdUsersSearchOu

# Fixed values
$propertiesToSelect = @(                    
    "SamAccountName",
    "DisplayName",
    "UserPrincipalName",
    "mail",
    "ObjectGuid",
    "EmployeeID"
) # Properties to select from Microsoft AD, comma separated

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

try {
    #region Searching user
    $actionMessage = "searching AD account(s) with the value entered [$($searchValue)]"

    if ([String]::IsNullOrEmpty($searchValue) -eq $true) {
        return
    }
    else {
        Write-Information "SearchQuery: $searchQuery"
        Write-Information "SearchBase: $searchOUs"
         
        $ous = $searchOUs -split ';'
        $users = foreach ($item in $ous) {
            $getAdUsersSplatParams = @{
                Filter      = $filter
                Searchbase  = $item
                Properties  = $propertiesToSelect
                Verbose     = $False
                ErrorAction = "Stop"
            }
            Get-AdUser @getAdUsersSplatParams | Select-Object -Property $propertiesToSelect
        }
         
        $users = $users | Sort-Object -Property DisplayName
        $resultCount = @($users).Count
        Write-Information "Result count: $resultCount"
         
        if ($resultCount -gt 0) {
            foreach ($user in $users) {
                Write-Output $user
            }
        }
    }
}
catch {
    $ex = $PSItem
    Write-Warning "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    Write-Error "Error $($actionMessage). Error: $($ex.Exception.Message)"
    # exit # use when using multiple try/catch and the script must stop
}
'@ 
$tmpModel = @'
[{"key":"SamAccountName","type":0},{"key":"DisplayName","type":0},{"key":"UserPrincipalName","type":0},{"key":"mail","type":0},{"key":"ObjectGuid","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchUser","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
AD AFAS Account - Update UPN - Email - Clone ad-afas-account-update-upn-email | AD-Get-Active-Users-DisplayName-Mail-Name-UserprincipalName
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "AD AFAS Account - Update UPN - Email - Clone ad-afas-account-update-upn-email | AD-Get-Active-Users-DisplayName-Mail-Name-UserprincipalName" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "AD AFAS Account - Update UPN - Email - Clone" #>
$tmpSchema = @"
[{"label":"Select user account","fields":[{"key":"searchfield","templateOptions":{"label":"Search","placeholder":"Username or Email"},"type":"input","summaryVisibility":"Hide element","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"gridUsers","templateOptions":{"label":"Select user account","required":true,"grid":{"columns":[{"headerName":"Display Name","field":"DisplayName"},{"headerName":"UserPrincipalName","field":"UserPrincipalName"},{"headerName":"Mail","field":"mail"},{"headerName":"Object Guid","field":"ObjectGuid"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchUser","otherFieldValue":{"otherFieldKey":"searchfield"}}]}},"useFilter":false,"allowCsvDownload":true},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Details","fields":[{"key":"blnMail","templateOptions":{"label":"Update E-mail","useSwitch":true,"checkboxLabel":""},"type":"boolean","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"formRowMail","templateOptions":{},"fieldGroup":[{"key":"currentMail","templateOptions":{"label":"Current E-mail Address","useDataSource":false,"useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"mail","readonly":true},"hideExpression":"!model[\"blnMail\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"newMail","templateOptions":{"label":"New E-mail Address","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"mail"},"hideExpression":"!model[\"blnMail\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"blnUPN","templateOptions":{"label":"Update user principal name","useSwitch":true,"checkboxLabel":""},"type":"boolean","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"formRowUPN","templateOptions":{},"fieldGroup":[{"key":"currentUPN","templateOptions":{"label":"Current user principal name","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"UserPrincipalName","readonly":true},"hideExpression":"!model[\"blnUPN\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"newUPN","templateOptions":{"label":"New user principal name","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"UserPrincipalName"},"hideExpression":"!model[\"blnUPN\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"Validation","templateOptions":{"label":"Validation","readonly":true,"useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[{"propertyName":"newUPN","otherFieldValue":{"otherFieldKey":"newUPN"}},{"propertyName":"newMail","otherFieldValue":{"otherFieldKey":"newMail"}},{"propertyName":"blnMail","otherFieldValue":{"otherFieldKey":"blnMail"}},{"propertyName":"blnUPN","otherFieldValue":{"otherFieldKey":"blnUPN"}},{"propertyName":"user","otherFieldValue":{"otherFieldKey":"gridUsers"}}]}},"displayField":"text","pattern":"^Valid.*"},"validation":{"messages":{"pattern":"No valid value"}},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
AD AFAS Account - Update UPN - Email - Clone
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null} 
$delegatedFormName = @'
AD Youforce Account - Update UPN - Email
'@
$tmpTask = @'
{"name":"AD Youforce Account - Update UPN - Email","script":"# variables configured in form:\r\n$user = $form.gridUsers\r\n$blnmail = [System.Convert]::ToBoolean($form.blnMail)\r\n$blnupn = [System.Convert]::ToBoolean($form.blnUPN)\r\n$blnidentity = $false\r\n$newMailAddress = $form.newMail\r\n$newUserPrincipalName = $form.newUPN\r\n$Script:AuthenticationUri = \"https://connect.visma.com/connect/token\"\r\n$Script:BaseUri = \"https://api.youforce.com\"\r\n$clientId = $BeaufortClientid\r\n$clientSecret = $BeaufortClientsecret\r\n$TenantId = $Beauforttenantid\r\n\r\n# Set debug logging\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\nfunction Resolve-HTTPError {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $httpErrorObj = [PSCustomObject]@{\r\n            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId\r\n            MyCommand             = $ErrorObject.InvocationInfo.MyCommand\r\n            RequestUri            = $ErrorObject.TargetObject.RequestUri\r\n            ScriptStackTrace      = $ErrorObject.ScriptStackTrace\r\n            ErrorMessage          = \u0027\u0027\r\n        }\r\n        if ($ErrorObject.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) {\r\n            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message\r\n        }\r\n        elseif ($ErrorObject.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027) {\r\n            $httpErrorObj.ErrorMessage = [HelloID.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\r\n        }\r\n        Write-Output $httpErrorObj\r\n    }\r\n}\r\nfunction Get-ErrorMessage {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $errorMessage = [PSCustomObject]@{\r\n            VerboseErrorMessage = $null\r\n            AuditErrorMessage   = $null\r\n        }\r\n\r\n        if ( $($ErrorObject.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) -or $($ErrorObject.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027)) {\r\n            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject\r\n\r\n            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage\r\n\r\n            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage\r\n        }\r\n\r\n        # If error message empty, fall back on $ex.Exception.Message\r\n        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {\r\n            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message\r\n        }\r\n        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {\r\n            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message\r\n        }\r\n\r\n        Write-Output $errorMessage\r\n    }\r\n}\r\n\r\nfunction New-RaetSession {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Alias(\"Param1\")] \r\n        [parameter(Mandatory = $true)]  \r\n        [string]      \r\n        $ClientId,\r\n\r\n        [Alias(\"Param2\")] \r\n        [parameter(Mandatory = $true)]  \r\n        [string]\r\n        $ClientSecret,\r\n\r\n        [Alias(\"Param3\")] \r\n        [parameter(Mandatory = $false)]  \r\n        [string]\r\n        $TenantId\r\n    )\r\n\r\n    #Check if the current token is still valid\r\n    $accessTokenValid = Confirm-AccessTokenIsValid\r\n    if ($true -eq $accessTokenValid) {\r\n        return\r\n    }\r\n\r\n    try {\r\n        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2\r\n        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12\r\n\r\n        $authorisationBody = @{\r\n            \u0027grant_type\u0027    = \"client_credentials\"\r\n            \u0027client_id\u0027     = $ClientId\r\n            \u0027client_secret\u0027 = $ClientSecret\r\n            \u0027tenant_id\u0027     = $TenantId\r\n        }        \r\n        $splatAccessTokenParams = @{\r\n            Uri             = $Script:AuthenticationUri\r\n            Headers         = @{\u0027Cache-Control\u0027 = \"no-cache\" }\r\n            Method          = \u0027POST\u0027\r\n            ContentType     = \"application/x-www-form-urlencoded\"\r\n            Body            = $authorisationBody\r\n            UseBasicParsing = $true\r\n        }\r\n\r\n        Write-Verbose \"Creating Access Token at uri \u0027$($splatAccessTokenParams.Uri)\u0027\"\r\n\r\n        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false\r\n        if ($null -eq $result.access_token) {\r\n            throw $result\r\n        }\r\n\r\n        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)\r\n\r\n        $Script:AuthenticationHeaders = @{\r\n            \u0027Authorization\u0027 = \"Bearer $($result.access_token)\"\r\n            \u0027Accept\u0027        = \"application/json\"\r\n        }\r\n\r\n        Write-Verbose \"Successfully created Access Token at uri \u0027$($splatAccessTokenParams.Uri)\u0027\"\r\n    }\r\n    catch {\r\n        $ex = $PSItem\r\n        $errorMessage = Get-ErrorMessage -ErrorObject $ex\r\n\r\n        Write-Verbose \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))\"\r\n\r\n        $auditLogs.Add([PSCustomObject]@{\r\n                # Action  = \"\" # Optional\r\n                Message = \"Error creating Access Token at uri \u0027\u0027$($splatAccessTokenParams.Uri)\u0027. Please check credentials. Error Message: $($errorMessage.AuditErrorMessage)\"\r\n                IsError = $true\r\n            })     \r\n    }\r\n}\r\n\r\nfunction Confirm-AccessTokenIsValid {\r\n    if ($null -ne $Script:expirationTimeAccessToken) {\r\n        if ((Get-Date) -le $Script:expirationTimeAccessToken) {\r\n            return $true\r\n        }\r\n    }\r\n    return $false\r\n}\r\n\r\ntry {\r\n    $actionMessage = \"updating AD attributes for user [$($user.userPrincipalName)] with objectguid [$($user.ObjectGuid)]\"\r\n\r\n    $proxyAddresses = @()\r\n    foreach ($address in $user.ProxyAddresses) {\r\n        if ($address.StartsWith(\u0027SMTP:\u0027)) {\r\n            $address = $address -replace \u0027SMTP:\u0027, \u0027smtp:\u0027\r\n        }\r\n        if ($address -eq \"smtp:\" + $newMailAddress) {\r\n        }\r\n        else {\r\n            $proxyAddresses += $address\r\n        }\r\n    }\r\n\r\n    $newPrimary = \u0027SMTP:\u0027 + $newMailAddress\r\n    $proxyAddresses += $newPrimary\r\n\r\n    if ($blnupn -eq $true) {\r\n        Set-ADUser -Identity $user.ObjectGuid -userprincipalname $newUserPrincipalName \r\n\r\n        $Log = @{\r\n            Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n            System            = \"ActiveDirectory\" # optional (free format text) \r\n            Message           = \"Successfully updated AD user [$($user.userPrincipalName)] attributes [userPrincipalName] from [$($user.userPrincipalName)] to [$newUserPrincipalName]\" # required (free format text) \r\n            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n            TargetIdentifier  = $user.ObjectGuid # optional (free format text) \r\n        }\r\n        #send result back  \r\n        Write-Information -Tags \"Audit\" -MessageData $log     \r\n    }\r\n\r\n    if ($blnmail -eq $true) {\r\n        Set-ADUser -Identity $user.ObjectGuid -emailaddress $newMailAddress -Replace @{proxyAddresses = $proxyAddresses }\r\n\r\n        $Log = @{\r\n            Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n            System            = \"ActiveDirectory\" # optional (free format text) \r\n            Message           = \"Successfully updated AD user [$($user.mail)] attributes [mail] from [$($user.mail)] to [$newMailAddress]\" # required (free format text) \r\n            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n            TargetIdentifier  = $user.ObjectGuid # optional (free format text) \r\n        }\r\n        #send result back  \r\n        Write-Information -Tags \"Audit\" -MessageData $log     \r\n    }\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"  \r\n\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"ActiveDirectory\" # optional (free format text) \r\n        Message           = \"Failed to update AD user [$($user.userPrincipalName)] attributes [userPrincipalName] from [$($user.userPrincipalName)] to [$newUserPrincipalName], [emailaddress] from [$($user.mail)] to [$newMailAddress]\" # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n        TargetIdentifier  = $user.ObjectGuid # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log      \r\n    Write-Warning $warningMessage   \r\n    Write-Error $auditMessage   \r\n}\r\n#endregion AD\r\n\r\n#region Beaufort contact details\r\ntry {\r\n\r\n    $accessTokenValid = Confirm-AccessTokenIsValid\r\n\r\n    if ($true -ne $accessTokenValid) {\r\n        New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId\r\n    }\r\n\r\n    $actionMessage = \"retrieving correlated account from Youforce API for person [$($user.EmployeeID)]\"\r\n    $splatWebRequest = @{\r\n        Uri             = \"$youforceBaseUrl/iam/v1.0/persons/$($user.EmployeeID)\"\r\n        Headers         = $headers\r\n        Method          = \u0027GET\u0027\r\n        ContentType     = \"application/json\"\r\n        UseBasicParsing = $true\r\n    }\r\n    $correlatedAccount = Invoke-RestMethod @splatWebRequest\r\n\r\n    if ($null -eq $correlatedAccount.id) {\r\n        throw \u0027No employee found in Youforce\u0027\r\n    }\r\n\r\n    $actionMessage = \"checking and updating business email attribute in Youforce for person [$($user.EmployeeID)]\"\r\n\r\n    if ($null -ne $correlatedAccount.emailAddresses) {\r\n        $businessEmailAddress = $correlatedAccount.emailAddresses | Where-Object { $_.type -eq \"Business\" }\r\n        $businessEmailAddressOld = $businessEmailAddress.address\r\n        if ([string]::IsNullOrEmpty($businessEmailAddressOld)) {\r\n            $businessEmailAddressOld = \u0027\u0027\r\n        }\r\n    }\r\n    else {\r\n        $businessEmailAddressOld = \u0027\u0027\r\n    }\r\n\r\n    if ($businessEmailAddressOld -ne $newMailAddress) {\r\n        $body = [PSCustomObject]@{\r\n            \u0027emailAddress\u0027 = $newMailAddress\r\n        }\r\n        $body = $body | ConvertTo-Json -Depth 10\r\n\r\n        $splatWebRequest = @{\r\n            Uri             = \"$youforceBaseUrl/iam/v1.0/ContactDetails/$($correlatedAccount.personCode)\"\r\n            Headers         = $headers\r\n            Method          = \u0027POST\u0027\r\n            Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n            ContentType     = \"application/json;charset=utf-8\"\r\n            UseBasicParsing = $true\r\n        }\r\n        $null = Invoke-RestMethod @splatWebRequest\r\n\r\n        $Log = @{\r\n            Action            = \"UpdateAccount\"\r\n            System            = \"Youforce\"\r\n            Message           = \"Successfully updated Youforce personCode [$($correlatedAccount.personCode)] attributes [businessmail] from [$businessEmailAddressOld] to [$newMailAddress]\"\r\n            IsError           = $false\r\n            TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n            TargetIdentifier  = $correlatedAccount.personCode # optional (free format text) \r\n        }\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n    }\r\n    else {\r\n        $Log = @{\r\n            Action            = \"UpdateAccount\"\r\n            System            = \"Youforce\"\r\n            Message           = \"Successfully checked Youforce person [$($correlatedAccount.personCode)] attributes [businessmail] [$businessEmailAddressOld], no changes needed\"\r\n            IsError           = $false\r\n            TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n            TargetIdentifier  = $correlatedAccount.personCode # optional (free format text) \r\n        }\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n    }\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if ($($ex.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) -or\r\n        $($ex.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027)) {\r\n        $errorObj = Resolve-YouforceError -ErrorObject $ex\r\n        $warningMessage = \"Error at Line \u0027$($errorObj.ScriptLineNumber)\u0027: $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\r\n    }\r\n    else {\r\n        $warningMessage = \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    }\r\n    $log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"Youforce\" # optional (free format text) \r\n        Message           = $auditMessage # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n        TargetIdentifier  = $correlatedAccount.personCode # optional (free format text) \r\n    }\r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n}\r\n#endregion Beaufort contact details\r\n\r\n#region Beaufort Identity\r\nif ($blnidentity -eq $true) {\r\n    try {\r\n\r\n        $accessTokenValid = Confirm-AccessTokenIsValid\r\n\r\n        if ($true -ne $accessTokenValid) {\r\n            New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId\r\n        }\r\n\r\n        $actionMessage = \"retrieving correlated account from Youforce API for user [$($user.EmployeeID)]\"\r\n        $splatWebRequest = @{\r\n            Uri             = \"$($Script:BaseUrl)/iam/v1.0/users(employeeId=$($user.EmployeeID))\"\r\n            Headers         = $Script:AuthenticationHeaders\r\n            Method          = \u0027GET\u0027\r\n            ContentType     = \"application/json\"\r\n            UseBasicParsing = $true\r\n        }\r\n        $correlatedAccount = Invoke-RestMethod @splatWebRequest\r\n\r\n        if ($null -eq $correlatedAccount.id) {\r\n            throw \u0027No user found in Youforce\u0027\r\n        }\r\n\r\n        $actionMessage = \"checking and updating business email attribute in Youforce for user [$($correlatedAccount.personCode)]\"\r\n\r\n        if ($null -ne $correlatedAccount.id) {\r\n            if ([string]$correlatedAccount.identityId -ne $newUserPrincipalName -and $null -ne $newUserPrincipalName) {\r\n                $updateAccount = [PSCustomObject]@{\r\n                    id = $newUserPrincipalName\r\n                }\r\n\r\n                $body = ($updateAccount | ConvertTo-Json -Depth 10) \r\n\r\n                $splatWebRequest = @{\r\n                    Uri             = \"$($Script:BaseUrl)/iam/v1.0/users(employeeId=$($user.EmployeeID))/identity\"\r\n                    Headers         = $Script:AuthenticationHeaders\r\n                    Method          = \u0027PATCH\u0027\r\n                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n                    ContentType     = \"application/json;charset=utf-8\"\r\n                    UseBasicParsing = $true\r\n                }\r\n                $null = Invoke-RestMethod @splatWebRequest\r\n\r\n                $Log = @{\r\n                    Action            = \"UpdateAccount\"\r\n                    System            = \"Youforce\"\r\n                    Message           = \"Successfully updated Youforce Identity [$($user.EmployeeID)] attributes [identity] from [$($correlatedAccount.identityId)] to [$($newUserPrincipalName)]\"\r\n                    IsError           = $false\r\n                    TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n                    TargetIdentifier  = $user.ObjectGuid # optional (free format text) \r\n                }\r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            else {\r\n                $Log = @{\r\n                    Action            = \"UpdateAccount\"\r\n                    System            = \"Youforce\"\r\n                    Message           = \"Successfully checked Youforce Identity [$($user.EmployeeID)] attributes [identity] [$($correlatedAccount.identityId)], no changes needed\"\r\n                    IsError           = $false\r\n                    TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n                    TargetIdentifier  = $user.ObjectGuid # optional (free format text) \r\n                }\r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n        }\r\n    }\r\n    catch {\r\n        $ex = $PSItem\r\n        if ($($ex.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) -or\r\n            $($ex.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027)) {\r\n            $errorObj = Resolve-YouforceError -ErrorObject $ex\r\n            $warningMessage = \"Error at Line \u0027$($errorObj.ScriptLineNumber)\u0027: $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\r\n            $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\r\n        }\r\n        else {\r\n            $warningMessage = \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n            $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n        }\r\n        $log = @{\r\n            Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n            System            = \"Youforce\" # optional (free format text) \r\n            Message           = $auditMessage # required (free format text) \r\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $user.userPrincipalName # optional (free format text) \r\n            TargetIdentifier  = $user.ObjectGuid # optional (free format text) \r\n        }\r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n        Write-Warning $warningMessage\r\n        Write-Error $auditMessage\r\n    }\r\n}\r\n#endregion Beaufort Identity\r\n","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-envelope" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

