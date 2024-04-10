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

#Global variable #1 >> Beauforttenantid
$tmpName = @'
Beauforttenantid
'@ 
$tmpValue = @'
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> BeaufortClientsecret
$tmpName = @'
BeaufortClientsecret
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});

#Global variable #3 >> BeaufortClientid
$tmpName = @'
BeaufortClientid
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #4 >> ADusersSearchOU
$tmpName = @'
ADusersSearchOU
'@ 
$tmpValue = @'
[{ "OU": "OU=Disabled Users,OU=HelloID Training,DC=veeken,DC=local"},{ "OU": "OU=Users,OU=HelloID Training,DC=veeken,DC=local"}]
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
<# Begin: DataSource "AD-Beaufort-account-update-upn-email-validation" #>
$tmpPsScript = @'
#######################################################################
# Template: CB HelloID SA Powershell data source
# Name:     AD-Beaufort-account-update-upn-email-validation
# Date:     24-10-2023
#######################################################################

# For basic information about powershell data sources see:
# https://docs.helloid.com/en/service-automation/dynamic-forms/data-sources/powershell-data-sources/add,-edit,-or-remove-a-powershell-data-source.html#add-a-powershell-data-source

# Service automation variables:
# https://docs.helloid.com/en/service-automation/service-automation-variables/service-automation-variable-reference.html

#region init

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$outputText = [System.Collections.Generic.List[PSCustomObject]]::new()


# global variables (Automation --> Variable libary):
# $globalVar = $globalVarName

# variables configured in form:
$upnEmailEqual = $datasource.upnEmailEqual
$userSID = $dataSource.selectedUser.SID

$upnCurrent = $dataSource.selectedUser.UserPrincipalName
$upnPrefixNew = $datasource.upnPrefix
$upnSuffixCurrent = $datasource.upnSuffixCurrent
$upnSuffixNew = $datasource.upnSuffixNew
if ([string]::IsNullOrEmpty($upnSuffixNew)) {
    $upnNew = $upnPrefixNew + $upnSuffixCurrent
}
else {
    $upnNew = $upnPrefixNew + $upnSuffixNew
}

if ($upnEmailEqual -eq "True") {
    $emailOrUpnNew = $upnNew
}
else {
    $emailCurrent = $dataSource.selectedUser.EmailAddress
    $emailPrefixNew = $datasource.emailPrefix
    $emailSuffixCurrent = $datasource.emailSuffixCurrent
    $emailSuffixNew = $datasource.emailSuffixNew
    if ([string]::IsNullOrEmpty($emailSuffixNew)) {
        $emailOrUpnNew = $emailPrefixNew + $emailSuffixCurrent
    }
    else {
        $emailOrUpnNew = $emailPrefixNew + $emailSuffixNew
    }
}

#endregion init

#region functions
# function Remove-StringLatinCharacters {
#     PARAM ([string]$String)
#     [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
# }
#endregion functions

#region lookup
try {
    if ($upnCurrent -eq $upnNew) {
        $outputText.Add([PSCustomObject]@{
                Message  = "UPN [$upnCurrent] not changed"
                IsError  = $true
                Property = "UPN"
            })
    }

    if (($emailCurrent -eq $emailOrUpnNew)) {
        $outputText.Add([PSCustomObject]@{
                Message  = "Email [$emailCurrent] not changed"
                IsError  = $true
                Property = "Email"
            })
    }
    
    # $upnNew = Remove-StringLatinCharacters $upnNew
    # $emailOrUpnNew = Remove-StringLatinCharacters $emailOrUpnNew

    # $pattern = "^[a-zA-Z0-9_%+-]+(\.[a-zA-Z0-9_%+-]+)*@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    # if (-not($upnNew -match $pattern)) {
    #     $outputText.Add([PSCustomObject]@{
    #             Message  = "UPN [$upnNew] invalid character(s) or pattern"
    #             IsError  = $true
    #             Property = "UPN"
    #         })
    # }

    # if ((-not($emailOrUpnNew -match $pattern))) {
    #     $outputText.Add([PSCustomObject]@{
    #             Message  = "Email [$emailOrUpnNew] invalid character(s) or pattern"
    #             IsError  = $true
    #             Property = "Email"
    #         })
    # }

    if (-not($outputText.isError -contains - $true)) {
        write-information "no errors"
        
        if ($upnEmailEqual -eq "True") {
            $searchUpperCase = "SMTP:$upnNew"
            $searchLowerCase = "smtp:$upnNew"
    
            $adUserParams = @{
                # Filter     = { (EmailAddress -eq $upnNew -or ProxyAddresses -eq SMTP:$upnNew -or ProxyAddresses -eq smtp:$upnNew -or userPrincipalName -eq $upnNew) -and (SID -ne $userSID) }
                Filter     = { (EmailAddress -eq $upnNew -or ProxyAddresses -eq $searchUpperCase -or ProxyAddresses -eq $searchLowerCase -or userPrincipalName -eq $upnNew) -and (SID -ne $userSID) }
                Properties = 'ProxyAddresses', 'userPrincipalName', 'EmailAddress'
            }
        }
        else { 
            $searchUpperCaseUPN = "SMTP:$upnNew"
            $searchLowerCaseUPN = "smtp:$upnNew"
            $searchUpperCaseEmail = "SMTP:$emailOrUpnNew"
            $searchLowerCaseEmail = "smtp:$emailOrUpnNew"

            $adUserParams = @{
                Filter     = { (EmailAddress -eq $emailOrUpnNew -or ProxyAddresses -eq $searchUpperCaseUPN -or ProxyAddresses -eq $searchLowerCaseUPN -or ProxyAddresses -eq $searchUpperCaseEmail -or ProxyAddresses -eq $searchLowerCaseEmail -or userPrincipalName -eq $upnNew) -and (SID -ne $userSID) }
                Properties = 'ProxyAddresses', 'userPrincipalName', 'EmailAddress'
            }
        }

        $found = Get-ADUser @adUserParams

        write-information "FOUND [$($found | Convertto-json)]"


        foreach ($record in $found) {
            if ($record.UserPrincipalName -eq $upnNew) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "UPN [$upnNew] not unique, found on [$($record.Name)]"
                        IsError  = $true
                        Property = "UPN"
                    })
            }
            if ($record.EmailAddress -eq $emailOrUpnNew) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "Email [$emailOrUpnNew] not unique, found on [$($record.Name)]"
                        IsError  = $true
                        Property = "Email"
                    })
            }
            elseif (($record.ProxyAddresses -eq "SMTP:$emailOrUpnNew") -or ($record.ProxyAddresses -eq "smtp:$emailOrUpnNew")) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "ProxyAddress [$emailOrUpnNew] not unique, found on [$($record.Name)]"
                        IsError  = $true
                        Property = "ProxyAddress"
                    })
            }
            elseif (($record.ProxyAddresses -eq "SMTP:$upnNew") -or ($record.ProxyAddresses -eq "smtp:$upnNew") -and ($upnNew -ne $emailOrUpnNew)) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "ProxyAddress [$upnNew] not unique, found on [$($record.Name)]"
                        IsError  = $true
                        Property = "ProxyAddress"
                    })
            }
            
            # Write-Information "UserPrincipalName [$($record.UserPrincipalName)]"
            # Write-Information "EmailAddress [$($record.EmailAddress)]"
            # Write-Information "ProxyAddresses [$($record.ProxyAddresses)]"
            # Write-Information "DistinguishedName [$($record.DistinguishedName)]"
        }

        # if (-not($outputText.Property -contains "UPN")) {
        #     $outputText.Add([PSCustomObject]@{
        #             Message  = "UPN [$upnNew] unique"
        #             IsError  = $false
        #             Property = "UPN"
        #         })
        # }
        # if (-not($outputText.Property -contains "Email")) {
        #     $outputText.Add([PSCustomObject]@{
        #             Message  = "Email [$emailOrUpnNew] unique"
        #             IsError  = $false
        #             Property = "Email"
        #         })
        # }
        # if (-not($outputText.Property -contains "ProxyAddress")) {
        #     $outputText.Add([PSCustomObject]@{
        #             Message  = "ProxyAddress [$emailOrUpnNew] unique"
        #             IsError  = $false
        #             Property = "ProxyAddress"
        #         })
        # }
    }

    if ($outputText.isError -contains - $true) {
        $outputMessage = "Invalid"
    }
    else {
        $outputMessage = "Valid"
        $outputText.Add([PSCustomObject]@{
                Message  = "UPN [$upnNew] unique"
                IsError  = $false
                Property = "UPN"
            })
        $outputText.Add([PSCustomObject]@{
                Message  = "Email [$emailOrUpnNew] unique"
                IsError  = $false
                Property = "Email"
            })
    }

    foreach ($text in $outputText) {
        $outputMessage += " | " + $($text.Message)
    }

    $returnObject = @{
        text              = $outputMessage
        userPrincipalName = $upnNew
        emailAddress      = $emailOrUpnNew
    }

    Write-Output $returnObject      
}
catch {
    $ex = $PSItem
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        
    Write-Error "Error querying data. Error Message: $($_ex.Exception.Message)" 
}
#endregion lookup
'@ 
$tmpModel = @'
[{"key":"text","type":0},{"key":"emailAddress","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"emailPrefix","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"emailSuffixCurrent","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"emailSuffixNew","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"selectedUser","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"upnPrefix","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"upnSuffixCurrent","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"upnSuffixNew","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"upnEmailEqual","type":0,"options":0}]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
AD-Beaufort-account-update-upn-email-validation
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "AD-Beaufort-account-update-upn-email-validation" #>

<# Begin: DataSource "AD-Beaufort-account-update-upn-email-lookup-user-generate-table" #>
$tmpPsScript = @'
#######################################################################
# Template: CB HelloID SA Powershell data source
# Name:     AD-Beaufort-account-update-upn-email-lookup-user-generate-table
# Date:     24-10-2023
#######################################################################

# For basic information about powershell data sources see:
# https://docs.helloid.com/en/service-automation/dynamic-forms/data-sources/powershell-data-sources/add,-edit,-or-remove-a-powershell-data-source.html#add-a-powershell-data-source

# Service automation variables:
# https://docs.helloid.com/en/service-automation/service-automation-variables/service-automation-variable-reference.html

#region init

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# global variables (Automation --> Variable libary):
$searchOUs = $ADusersSearchOU

# variables configured in form:
$searchValue = $dataSource.searchUser
$searchQuery = "*$searchValue*"

#endregion init

#region functions

#endregion functions

#region lookup
try {
    if ([String]::IsNullOrEmpty($searchValue) -eq $true) {
        return
    }
    else {
        Write-Verbose "SearchQuery: $searchQuery"
        Write-Verbose "SearchBase: $searchOUs"
        
        $ous = $searchOUs | ConvertFrom-Json
        $users = foreach ($item in $ous) {
            Get-ADUser -Filter { Name -like $searchQuery -or userPrincipalName -like $searchQuery -or mail -like $searchQuery } -SearchBase $item.ou -properties displayName, UserPrincipalName, EmailAddress, EmployeeID, GivenName, SurName
        }
    
        # Filter users without employeeID
        $users = $users | Where-Object { $null -ne $_.employeeID }

        $users = $users | Sort-Object -Property DisplayName

        Write-Verbose "Successfully queried data. Result count: $(($users | Measure-Object).Count)"

        if (($users | Measure-Object).Count -gt 0) {
            foreach ($user in $users) {
                # Split UserPrincipalName and EmailAddress for semperate editing
                if (-not([string]::IsNullOrEmpty($user.UserPrincipalName))) {
                    $userPrincipalNameSplit = $($user.UserPrincipalName).Split("@")
                    $userPrincipalNamePrefix = $userPrincipalNameSplit[0]
                    $userPrincipalNameSuffix = "@" + $userPrincipalNameSplit[1]
                }
                if (-not([string]::IsNullOrEmpty($user.EmailAddress))) {
                    $emailAddressSplit = $($user.EmailAddress).Split("@")
                    $emailAddressPrefix = $emailAddressSplit[0]
                    $emailAddressSuffix = "@" + $emailAddressSplit[1]
                }
                $returnObject = @{
                    displayName             = $user.DisplayName
                    UserPrincipalName       = $user.UserPrincipalName
                    EmployeeID              = $user.EmployeeID
                    EmailAddress            = $user.EmailAddress
                    EmailAddressPrefix      = $emailAddressPrefix
                    EmailAddressSuffix      = $emailAddressSuffix
                    UserPrincipalNamePrefix = $userPrincipalNamePrefix
                    UserPrincipalNameSuffix = $userPrincipalNameSuffix
                    GivenName               = $user.GivenName
                    SurName                 = $user.SurName
                    SID                     = $([string]$user.SID)
                }    
                Write-Output $returnObject      
            }
        }
    }
}
catch {
    $ex = $PSItem
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        
    Write-Error "Error retrieving AD user [$userPrincipalName] basic attributes. Error: $($_.Exception.Message)"
}
#endregion lookup
'@ 
$tmpModel = @'
[{"key":"GivenName","type":0},{"key":"EmailAddressPrefix","type":0},{"key":"UserPrincipalNameSuffix","type":0},{"key":"UserPrincipalNamePrefix","type":0},{"key":"UserPrincipalName","type":0},{"key":"SID","type":0},{"key":"displayName","type":0},{"key":"EmailAddress","type":0},{"key":"EmployeeID","type":0},{"key":"EmailAddressSuffix","type":0},{"key":"SurName","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchUser","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
AD-Beaufort-account-update-upn-email-lookup-user-generate-table
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "AD-Beaufort-account-update-upn-email-lookup-user-generate-table" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "AD Beaufort Account - Update UPN - Email" #>
$tmpSchema = @"
[{"label":"Select user account","fields":[{"key":"searchfield","templateOptions":{"label":"Search","placeholder":"Username or Email"},"type":"input","summaryVisibility":"Hide element","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"gridUsers","templateOptions":{"label":"Select user account","required":true,"grid":{"columns":[{"headerName":"Employee ID","field":"EmployeeID"},{"headerName":"Display Name","field":"displayName"},{"headerName":"User Principal Name","field":"UserPrincipalName"},{"headerName":"Email Address","field":"EmailAddress"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchUser","otherFieldValue":{"otherFieldKey":"searchfield"}}]}},"useFilter":false},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Details","fields":[{"key":"formRowUPN","templateOptions":{},"fieldGroup":[{"key":"upnPrefix","templateOptions":{"label":"Current user principal name prefix","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"UserPrincipalNamePrefix","pattern":"^[a-zA-Z0-9_%+-]+(\\.[a-zA-Z0-9_%+-]+)*","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"upnSuffixCurrent","templateOptions":{"label":"Current user principal name suffix","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"UserPrincipalNameSuffix","readonly":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"upnSuffixNew","templateOptions":{"label":"New user principal name suffix","required":false,"useObjects":false,"useDataSource":false,"useFilter":false,"options":["@wdodelta.nl"]},"type":"dropdown","defaultValue":"@wdodelta.nl","summaryVisibility":"Show","textOrLabel":"text","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"upnEmailEqual","templateOptions":{"label":"User principal name and email have the same value","useSwitch":true,"checkboxLabel":""},"type":"boolean","defaultValue":true,"summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"formRowEmail","templateOptions":{},"fieldGroup":[{"key":"emailPrefix","templateOptions":{"label":"Current email prefix","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"EmailAddressPrefix","readonly":false,"pattern":"^[a-zA-Z0-9_%+-]+(\\.[a-zA-Z0-9_%+-]+)*"},"validation":{"messages":{"pattern":""}},"hideExpression":"model[\"upnEmailEqual\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"emailSuffixCurrent","templateOptions":{"label":"Current email suffix","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"EmailAddressSuffix","readonly":true},"validation":{"messages":{"pattern":""}},"hideExpression":"model[\"upnEmailEqual\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"emailSuffixNew","templateOptions":{"label":"New email suffix","required":false,"useObjects":false,"useDataSource":false,"useFilter":false,"options":["@wdodelta.nl"]},"hideExpression":"model[\"upnEmailEqual\"]","type":"dropdown","defaultValue":"@wdodelta.nl","summaryVisibility":"Show","textOrLabel":"text","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"validate","templateOptions":{"label":"Validation","readonly":true,"required":true,"pattern":"^Valid.*","useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[{"propertyName":"emailPrefix","otherFieldValue":{"otherFieldKey":"emailPrefix"}},{"propertyName":"emailSuffixCurrent","otherFieldValue":{"otherFieldKey":"emailSuffixCurrent"}},{"propertyName":"emailSuffixNew","otherFieldValue":{"otherFieldKey":"emailSuffixNew"}},{"propertyName":"selectedUser","otherFieldValue":{"otherFieldKey":"gridUsers"}},{"propertyName":"upnPrefix","otherFieldValue":{"otherFieldKey":"upnPrefix"}},{"propertyName":"upnSuffixCurrent","otherFieldValue":{"otherFieldKey":"upnSuffixCurrent"}},{"propertyName":"upnSuffixNew","otherFieldValue":{"otherFieldKey":"upnSuffixNew"}},{"propertyName":"upnEmailEqual","otherFieldValue":{"otherFieldKey":"upnEmailEqual"}}]}},"displayField":"text","minLength":1},"validation":{"messages":{"pattern":"No valid value"}},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
AD Beaufort Account - Update UPN - Email
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
AD Beaufort Account - Update UPN - Email
'@
$tmpTask = @'
{"name":"AD Beaufort Account - Update UPN - Email","script":"#######################################################################\r\n# Template: RHo HelloID SA Delegated form task\r\n# Name:     AD-account-update-upn-email\r\n# Date:     24-10-2023\r\n#######################################################################\r\n\r\n# For basic information about delegated form tasks see:\r\n# https://docs.helloid.com/en/service-automation/delegated-forms/delegated-form-powershell-scripts/add-a-powershell-script-to-a-delegated-form.html\r\n\r\n# Service automation variables:\r\n# https://docs.helloid.com/en/service-automation/service-automation-variables/service-automation-variable-reference.html\r\n$dryRun = $false\r\n#region init\r\n# Set TLS to accept TLS, TLS 1.1 and TLS 1.2\r\n[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12\r\n\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n# global variables (Automation --\u003e Variable libary):\r\n# $globalVar = $globalVarName\r\n\r\n# variables configured in form:\r\n$currentEmail =#$form.gridUsers.EmailAddress\r\n$currentUPN = $form.gridUsers.UserPrincipalName\r\n$emailPrefix =  $form.emailPrefix\r\n$emailSuffixCurrent = $form.emailSuffixCurrent\r\n$emailSuffixNew = $form.emailSuffixNew\r\n$upnPrefix = $form.upnPrefix\r\n$upnSuffixCurrent = $form.upnSuffixCurrent\r\n$upnSuffixNew = $form.upnSuffixNew\r\n$employeeID = $form.gridUsers.employeeID\r\n$displayName = $form.gridUsers.displayName\r\n$upnEmailEqual = $form.upnEmailEqual\r\n\r\n$correlationProperty = \"personCode\"\r\n$correlationValue = $employeeID\r\n\r\n#endregion init\r\n\r\n#region global\r\n\r\nif ([string]::IsNullOrEmpty($upnSuffixNew)) {\r\n    $newUPN = $upnPrefix + $upnSuffixCurrent\r\n}\r\nelse {\r\n    $newUPN = $upnPrefix + $upnSuffixNew\r\n}\r\n\r\nif ($upnEmailEqual -eq \"True\") {\r\n    $newEmail = $newUPN\r\n}\r\nelse {\r\n    if ([string]::IsNullOrEmpty($emailSuffixNew)) {\r\n        $newEmail = $emailPrefix + $emailSuffixCurrent\r\n    }\r\n    else {\r\n        $newEmail = $emailPrefix + $emailSuffixNew\r\n    }\r\n}\r\n\r\n#endregion global\r\n\r\n#region AD\r\n# Search user\r\ntry {\r\n    $properties = @(\u0027SID\u0027, \u0027ObjectGuid\u0027, \u0027UserPrincipalName\u0027, \u0027SamAccountName\u0027, \u0027Mail\u0027, \u0027ProxyAddresses\u0027, \u0027EmployeeId\u0027)\r\n    $adUser = Get-ADuser -Filter { UserPrincipalName -eq $currentUPN } -Properties $properties\r\n    Write-Information \"Found AD user [$currentUPN]\"\r\n    \r\n}\r\ncatch {\r\n    Write-Error \"Could not find AD user [$currentUPN]. Error: $($_.Exception.Message)\"    \r\n}\r\n\r\n# Set UPN\r\ntry {\r\n\r\n    Set-ADUser -Identity $adUser -userprincipalname $newUPN\r\n    \r\n    Write-Information \"Finished update attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]\"\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"ActiveDirectory\" # optional (free format text) \r\n        Message           = \"Successfully updated attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $adUser.name # optional (free format text) \r\n        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log    \r\n}\r\ncatch {\r\n    Write-Error \"Could not update attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]. Error: $($_.Exception.Message)\"\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"ActiveDirectory\" # optional (free format text) \r\n        Message           = \"Failed to update attribute [userprincipalname] of AD user [$($adUser.SID)] from [$currentUPN] to [$newUPN]\" # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $adUser.name # optional (free format text) \r\n        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log      \r\n}\r\n\r\n# Set EmailAdress and update proxyAddresses\r\ntry {\r\n    $proxyAddresses = @()\r\n    foreach ($address in $adUSer.ProxyAddresses) {\r\n        if ($address.StartsWith(\u0027SMTP:\u0027)) {\r\n            $address = $address -replace \u0027SMTP:\u0027, \u0027smtp:\u0027\r\n        }\r\n        if ($address -eq \"smtp:\" + $newEmail) {\r\n        }\r\n        else {\r\n            $proxyAddresses += $address\r\n        }\r\n    }\r\n\r\n    $newPrimary = \u0027SMTP:\u0027 + $newEmail\r\n    $proxyAddresses += $newPrimary\r\n\r\n    Set-ADUser -Identity $adUSer -emailaddress $newEmail -Replace @{proxyAddresses = $proxyAddresses }\r\n\r\n    Write-Information \"Finished update attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]\"\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"ActiveDirectory\" # optional (free format text) \r\n        Message           = \"Successfully updated attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $adUser.name # optional (free format text) \r\n        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log        \r\n}\r\ncatch {\r\n    Write-Error \"Could not update attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]. Error: $($_.Exception.Message)\"\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"ActiveDirectory\" # optional (free format text) \r\n        Message           = \"Failed to update attribute [emailaddress] of AD user [$($adUser.SID)] from [$currentEmail] to [$newEmail]\" # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $adUser.name # optional (free format text) \r\n        TargetIdentifier  = $([string]$adUser.SID) # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log     \r\n}\r\n#endregion AD\r\n\r\n#region Beaufort\r\nfunction Resolve-HTTPError {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $httpErrorObj = [PSCustomObject]@{\r\n            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId\r\n            MyCommand             = $ErrorObject.InvocationInfo.MyCommand\r\n            RequestUri            = $ErrorObject.TargetObject.RequestUri\r\n            ScriptStackTrace      = $ErrorObject.ScriptStackTrace\r\n            ErrorMessage          = \u0027\u0027\r\n        }\r\n        if ($ErrorObject.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) {\r\n            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message\r\n        }\r\n        elseif ($ErrorObject.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027) {\r\n            $httpErrorObj.ErrorMessage = [HelloID.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\r\n        }\r\n        Write-Output $httpErrorObj\r\n    }\r\n}\r\nfunction Get-ErrorMessage {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $errorMessage = [PSCustomObject]@{\r\n            VerboseErrorMessage = $null\r\n            AuditErrorMessage   = $null\r\n        }\r\n\r\n        if ( $($ErrorObject.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) -or $($ErrorObject.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027)) {\r\n            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject\r\n\r\n            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage\r\n\r\n            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage\r\n        }\r\n\r\n        # If error message empty, fall back on $ex.Exception.Message\r\n        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {\r\n            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message\r\n        }\r\n        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {\r\n            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message\r\n        }\r\n\r\n        Write-Output $errorMessage\r\n    }\r\n}\r\n\r\nfunction New-RaetSession {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Alias(\"Param1\")] \r\n        [parameter(Mandatory = $true)]  \r\n        [string]      \r\n        $ClientId,\r\n\r\n        [Alias(\"Param2\")] \r\n        [parameter(Mandatory = $true)]  \r\n        [string]\r\n        $ClientSecret,\r\n\r\n        [Alias(\"Param3\")] \r\n        [parameter(Mandatory = $false)]  \r\n        [string]\r\n        $TenantId\r\n    )\r\n\r\n    #Check if the current token is still valid\r\n    $accessTokenValid = Confirm-AccessTokenIsValid\r\n    if ($true -eq $accessTokenValid) {\r\n        return\r\n    }\r\n\r\n    try {\r\n        # Set TLS to accept TLS, TLS 1.1 and TLS 1.2\r\n        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12\r\n\r\n        $authorisationBody = @{\r\n            \u0027grant_type\u0027    = \"client_credentials\"\r\n            \u0027client_id\u0027     = $ClientId\r\n            \u0027client_secret\u0027 = $ClientSecret\r\n            \u0027tenant_id\u0027     = $TenantId\r\n        }        \r\n        $splatAccessTokenParams = @{\r\n            Uri             = $Script:AuthenticationUri\r\n            Headers         = @{\u0027Cache-Control\u0027 = \"no-cache\" }\r\n            Method          = \u0027POST\u0027\r\n            ContentType     = \"application/x-www-form-urlencoded\"\r\n            Body            = $authorisationBody\r\n            UseBasicParsing = $true\r\n        }\r\n\r\n        Write-Verbose \"Creating Access Token at uri \u0027$($splatAccessTokenParams.Uri)\u0027\"\r\n\r\n        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false\r\n        if ($null -eq $result.access_token) {\r\n            throw $result\r\n        }\r\n\r\n        $Script:expirationTimeAccessToken = (Get-Date).AddSeconds($result.expires_in)\r\n\r\n        $Script:AuthenticationHeaders = @{\r\n            \u0027Authorization\u0027 = \"Bearer $($result.access_token)\"\r\n            \u0027Accept\u0027        = \"application/json\"\r\n        }\r\n\r\n        Write-Verbose \"Successfully created Access Token at uri \u0027$($splatAccessTokenParams.Uri)\u0027\"\r\n    }\r\n    catch {\r\n        $ex = $PSItem\r\n        $errorMessage = Get-ErrorMessage -ErrorObject $ex\r\n\r\n        Write-Verbose \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))\"\r\n\r\n        $auditLogs.Add([PSCustomObject]@{\r\n                # Action  = \"\" # Optional\r\n                Message = \"Error creating Access Token at uri \u0027\u0027$($splatAccessTokenParams.Uri)\u0027. Please check credentials. Error Message: $($errorMessage.AuditErrorMessage)\"\r\n                IsError = $true\r\n            })     \r\n    }\r\n}\r\n\r\n\r\n\r\n\r\nfunction Confirm-AccessTokenIsValid {\r\n    if ($null -ne $Script:expirationTimeAccessToken) {\r\n        if ((Get-Date) -le $Script:expirationTimeAccessToken) {\r\n            return $true\r\n        }\r\n    }\r\n    return $false\r\n}\r\n# Used to connect to Beaufort API endpoints\r\n$Script:AuthenticationUri = \"https://connect.visma.com/connect/token\"\r\n$Script:BaseUri = \"https://api.youforce.com\"\r\n\r\n$clientId = $BeaufortClientid\r\n$clientSecret = $BeaufortClientsecret\r\n$TenantId = $Beauforttenantid\r\n\r\n\r\n#Change mapping here\r\n$account = [PSCustomObject]@{\r\n    emailAddress = $newUPN\r\n    #phoneNumber  = $phoneFixed\r\n}\r\n\r\n$filterfieldid = \"Medewerker\"\r\n$filtervalue = $employeeID # Has to match the Beaufort value of the specified filter field ($filterfieldid)\r\n\r\n# Get current account and verify if the action should be either [updated and correlated] or just [correlated]\r\ntry {\r\n\r\n    $accessTokenValid = Confirm-AccessTokenIsValid\r\n\r\n    if ($true -ne $accessTokenValid) {\r\n        New-RaetSession -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId\r\n    }\r\n\r\n    Write-Verbose \"Querying Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n\r\n    $splatWebRequest = @{\r\n        Uri             = \"$($Script:BaseUri)/iam/v1.0/persons/$($correlationValue)\"\r\n        Headers         = $Script:AuthenticationHeaders\r\n        Method          = \u0027GET\u0027\r\n        ContentType     = \"application/json\"\r\n        UseBasicParsing = $true\r\n    }\r\n    $currentAccount = $null\r\n    $currentAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false\r\n\r\n\r\n    if ($null -ne $currentAccount.id) {\r\n        Write-Verbose \"Successfully found Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n    } \r\n    else {\r\n        throw \"No employee found in Raet Beaufort with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n    }\r\n\r\n\r\n    # Get value of current Business Email Address\r\n    if ($null -ne $currentAccount.emailAddresses) {\r\n        $businessEmailAddress = $currentAccount.emailAddresses | Where-Object { $_.type -eq \"Business\" }\r\n        $businessEmailAddressValue = $businessEmailAddress.address\r\n    }\r\n\r\n    # Retrieve current account data for properties to be updated\r\n    $previousAccount = [PSCustomObject]@{\r\n        \u0027emailAddress\u0027 = $businessEmailAddressValue\r\n        #\u0027phoneNumber\u0027  = $businessPhoneNumberValue\r\n    }\r\n    \r\n    $splatCompareProperties = @{\r\n        ReferenceObject  = @($previousAccount.PSObject.Properties)\r\n        DifferenceObject = @($account.PSObject.Properties)\r\n    }\r\n    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where( { $_.SideIndicator -eq \u0027=\u003e\u0027 })\r\n    \r\n    if ($propertiesChanged) {\r\n        Write-Verbose \"Account property(s) required to update: [$($propertiesChanged.name -join \",\")]\"\r\n    \r\n        foreach ($changedProperty in $propertiesChanged) {\r\n            Write-Verbose \"Updating field $($changedProperty.name) \u0027$($previousAccount.($changedProperty.name))\u0027 with new value \u0027$($account.($changedProperty.name))\u0027\"\r\n        }\r\n\r\n        $updateAction = \u0027Update\u0027\r\n    }\r\n    else {\r\n        $updateAction = \u0027NoChanges\u0027\r\n    }\r\n\r\n    switch ($updateAction) {\r\n        \u0027Update\u0027 {\r\n\r\n            try {\r\n                $body = ($account | ConvertTo-Json -Depth 10)\r\n                $splatWebRequest = @{\r\n                    Uri             = \"$($Script:BaseUri)/iam/v1.0/ContactDetails/$($correlationValue)\"\r\n                    Headers         = $Script:AuthenticationHeaders\r\n                    Method          = \u0027POST\u0027\r\n                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n                    ContentType     = \"application/json;charset=utf-8\"\r\n                    UseBasicParsing = $true\r\n                }\r\n\r\n                Write-Verbose \"Updating Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027. Account object: $($account | ConvertTo-Json -Depth 10)\"\r\n                                \r\n                if (-not($dryRun -eq $true)) {\r\n                    \r\n                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false\r\n\r\n                    $auditLogs.Add([PSCustomObject]@{\r\n                            # Action  = \"\" # Optional\r\n                            Message = \"Successfully updated Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n                            IsError = $false\r\n                        })\r\n                }\r\n                else {\r\n                    Write-Warning \"DryRun: Would update Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027. Account object: $($account | ConvertTo-Json -Depth 10)\"\r\n                }\r\n\r\n                break\r\n            }\r\n            catch {\r\n                $ex = $PSItem\r\n                $errorMessage = Get-ErrorMessage -ErrorObject $ex\r\n\r\n                Write-Verbose \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))\"\r\n                    \r\n                $Log = @{\r\n                    Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n                    System            = \"Beaufort Employee\" # optional (free format text) \r\n                    Message           = \"Successfully updated attribute [EmAd] of Beaufort emplyee [$employeeID] from [$($currentAccount.Email_werk)] to [$newEmail]\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $displayName # optional (free format text) \r\n                    TargetIdentifier  = $([string]$employeeID) # optional (free format text) \r\n                }\r\n            }\r\n        }\r\n        \u0027NoChanges\u0027 {\r\n\r\n            Write-Verbose \"No changes to Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n        \r\n            if (-not($dryRun -eq $true)) {\r\n\r\n                $Log = @{\r\n                    Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n                    System            = \"Beaufort Employee\" # optional (free format text) \r\n                    Message           = \"Skipped update attribute [EmAd] of Beaufort employee [$employeeID] to [$newEmail]: No Beaufort employee found with $($filterfieldid) $($filtervalue)\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $displayName # optional (free format text) \r\n                    TargetIdentifier  = $([string]$employeeID) # optional (free format text)\r\n                }\r\n            }\r\n            else {\r\n                Write-Warning \"DryRun: No changes to Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n            }                  \r\n\r\n            break\r\n        }\r\n    }\r\n}\r\n\r\ncatch {\r\n\r\n    $ex = $PSItem\r\n    if ( $($ex.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) -or $($ex.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027)) {\r\n        $errorObject = Resolve-HTTPError -Error $ex\r\n\r\n        $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n        $auditErrorMessage = Resolve-BeaufortErrorMessage -ErrorObject $errorObject.ErrorMessage\r\n    }\r\n\r\n    # If error message empty, fall back on $ex.Exception.Message\r\n    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n        $verboseErrorMessage = $ex.Exception.Message\r\n    }\r\n    if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n        $auditErrorMessage = $ex.Exception.Message\r\n    }\r\n\r\n    Write-Verbose \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n\r\n    if ($auditErrorMessage -Like \"No Beaufort employee found with $($filterfieldid) $($filtervalue)\") {\r\n        Write-Error \"Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: No Beaufort employee found with $($filterfieldid) $($filtervalue)\"\r\n        Write-Information \"Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: No Beaufort employee found with $($filterfieldid) $($filtervalue)\"\r\n        $Log = @{\r\n            Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n            System            = \"Beaufort Employee\" # optional (free format text) \r\n            Message           = \"Failed to update attribute [Mail] of Beaufort employee [$employeeId] to [$businessEmailAddressValue]: No Beaufort employee found with $($filterfieldid) $($filtervalue)\" # required (free format text) \r\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $displayName # optional (free format text) \r\n            TargetIdentifier  = $([string]$employeeID) # optional (free format text) \r\n        }\r\n        #send result back  \r\n        Write-Information -Tags \"Audit\" -MessageData $log \r\n    }\r\n    else {\r\n        Write-Error \"Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: Error querying Beaufort employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage\"\r\n        Write-Information \"Failed to update attribute [Mail] of Beaufort emplyee [$employeeID] to [$businessEmailAddressValue]: Error querying Beaufort employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage\"\r\n        $Log = @{\r\n            Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n            System            = \"Beaufort Employee\" # optional (free format text) \r\n            Message           = \"Failed to update attribute [Mail] of Beaufort employee [$employeeId] to $businessEmailAddressValue]: Error querying Beaufort employee found with $($filterfieldid) $($filtervalue). Error Message: $auditErrorMessage\" # required (free format text) \r\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $displayName # optional (free format text) \r\n            TargetIdentifier  = $([string]$employeeID) # optional (free format text) \r\n        }\r\n        #send result back  \r\n        Write-Information -Tags \"Audit\" -MessageData $log  \r\n    }\r\n}\r\n\r\n# Update Beaufort Employee\r\ntry {\r\n    Write-Information \"Start updating Beaufort employee [$($currentAccount.Medewerker)]\"\r\n    switch ($updateAction) {\r\n        \u0027Update\u0027 {\r\n            try {\r\n                $body = ($account | ConvertTo-Json -Depth 10)\r\n                $splatWebRequest = @{\r\n                    Uri             = \"$($Script:BaseUri)/iam/v1.0/ContactDetails/$($correlationValue)\"\r\n                    Headers         = $Script:AuthenticationHeaders\r\n                    Method          = \u0027POST\u0027\r\n                    Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))\r\n                    ContentType     = \"application/json;charset=utf-8\"\r\n                    UseBasicParsing = $true\r\n                }\r\n\r\n                Write-Verbose \"Updating Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027. Account object: $($account | ConvertTo-Json -Depth 10)\"\r\n                                \r\n                if (-not($dryRun -eq $true)) {\r\n                    \r\n                    $updatedAccount = Invoke-RestMethod @splatWebRequest -Verbose:$false\r\n\r\n                    $Log = @{\r\n                        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n                        System            = \"Beaufort Employee\" # optional (free format text) \r\n                        Message           = \"Successfully updated attribute [EmAd] of Beaufort emplyee [$employeeID] from [$($currentAccount.Email_werk)] to [$newEmail]\" # required (free format text) \r\n                        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                        TargetDisplayName = $displayName # optional (free format text) \r\n                        TargetIdentifier  = $([string]$employeeID) # optional (free format text) \r\n                    }\r\n                }\r\n                else {\r\n                    Write-Warning \"DryRun: Would update Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027. Account object: $($account | ConvertTo-Json -Depth 10)\"\r\n                }\r\n\r\n                break\r\n            }\r\n            catch {\r\n                $ex = $PSItem\r\n                $errorMessage = Get-ErrorMessage -ErrorObject $ex\r\n                        \r\n                Write-Verbose \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))\"\r\n                    \r\n                $auditLogs.Add([PSCustomObject]@{\r\n                        # Action  = \"\" # Optional\r\n                        Message = \"Error updating Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027. Error Message: $($errorMessage.AuditErrorMessage) Account object: $($account | ConvertTo-Json -Depth 10)\"\r\n                        IsError = $true\r\n                    })\r\n            }\r\n        }\r\n        \u0027NoChanges\u0027 {\r\n            Write-Verbose \"No changes to Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n        \r\n            if (-not($dryRun -eq $true)) {\r\n                $Log = @{\r\n                    Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n                    System            = \"Beaufort Employee\" # optional (free format text) \r\n                    Message           = \"Successfully checked attribute [EmAd] of Beaufort emplyee [$employeeID] from [$($currentAccount.Email_werk)] to [$newEmail], no changes needed\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = $displayName # optional (free format text) \r\n                    TargetIdentifier  = $([string]$employeeID) # optional (free format text) \r\n                }\r\n            }\r\n            else {\r\n                Write-Warning \"DryRun: No changes to Raet Beaufort employee with $($correlationProperty) \u0027$($correlationValue)\u0027\"\r\n            }                  \r\n\r\n            break\r\n        }\r\n    }\r\n\r\n    # Set aRef object for use in futher actions\r\n    $aRef = $currentAccount.personCode\r\n\r\n    # Define ExportData with account fields and correlation property \r\n    $exportData = $account.PsObject.Copy()\r\n    $exportData | Add-Member -MemberType NoteProperty -Name $correlationProperty -Value $correlationValue -Force\r\n\r\n    break\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if ( $($ex.Exception.GetType().FullName -eq \u0027Microsoft.PowerShell.Commands.HttpResponseException\u0027) -or $($ex.Exception.GetType().FullName -eq \u0027System.Net.WebException\u0027)) {\r\n        $errorObject = Resolve-HTTPError -Error $ex\r\n\r\n        $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n        $auditErrorMessage = Resolve-BeaufortErrorMessage -ErrorObject $errorObject.ErrorMessage\r\n    }\r\n\r\n    # If error message empty, fall back on $ex.Exception.Message\r\n    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n        $verboseErrorMessage = $ex.Exception.Message\r\n    }\r\n    if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n        $auditErrorMessage = $ex.Exception.Message\r\n    }\r\n\r\n    $ex = $PSItem\r\n    $verboseErrorMessage = $ex\r\n    \r\n    Write-Verbose \"Error at Line \u0027$($ex.InvocationInfo.ScriptLineNumber)\u0027: $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n    Write-Error \"Error updating Beaufort employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage\"\r\n    Write-Information \"Error updating Beaufort employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage\"\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"Beaufort Employee\" # optional (free format text) \r\n        Message           = \"Error updating Beaufort employee $($currentAccount.Medewerker). Error Message: $auditErrorMessage\" # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $displayName # optional (free format text) \r\n        TargetIdentifier  = $([string]$employeeID) # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log \r\n}\r\n#endregion Beaufort","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-envelope" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

