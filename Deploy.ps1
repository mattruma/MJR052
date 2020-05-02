param (
    [string]$LocationName,
    [string]$Name
)

If ($LocationName.Trim() -eq "" ) { 
    $LocationName = Read-Host -Prompt "Enter region for deployment, e.g. eastus2"
}

If ($LocationName.Trim() -eq "" ) { 
    Throw "Region is required, either enter as a prompt or provide a value for the -LocationName argument"
}

If ($Name.Trim() -eq "" ) {     
    $Name = ([char[]]([char]65..[char]90) + ([char[]]([char]97..[char]122)) + 0..9 | Sort-Object { Get-Random })[0..12] -Join ""
}

$ResourceGroupName = "$($Name)-rg"
$AppServicePlanName = "$($Name)-plan"
$ApplicationInsightsName = "$($Name)-appi"
$WebAppName = "$($Name)-app"

Write-Host "Creating the following resources in $($LocationName):" -ForegroundColor Gray
Write-Host ""
Write-Host "Resource Group       : $($ResourceGroupName)" -ForegroundColor Blue
Write-Host "App Service Plan     : $($AppServicePlanName)" -ForegroundColor Blue
Write-Host "Application Insights : $($ApplicationInsightsName)" -ForegroundColor Blue
Write-Host "Application Service  : $($WebAppName)" -ForegroundColor Blue
Write-Host ""

# Create resource group
az group create -n $ResourceGroupName -l $LocationName --tags Technologies="Authentication/Authorization, ExpressAuth, Web App, App Registration, Service Principal, Managed Identity"

# Create app service plan
az appservice plan create -g $ResourceGroupName -n $AppServicePlanName -l $LocationName --sku B1

# Create application insights
$ApplicationInsights = (az monitor app-insights component create --app $ApplicationInsightsName --l $LocationName -g $ResourceGroupName)

$ApplicationInsightsObject = $ApplicationInsights | ConvertFrom-Json

# Create web app
az webapp create -g $ResourceGroupName -p $AppServicePlanName -n $WebAppName

#Enable application logging on the web app
az webapp log config -g $ResourceGroupName -n $WebAppName --application-logging true --detailed-error-messages true --level verbose

# Add app settings
az webapp config appsettings set -g $ResourceGroupName -n $WebAppName --settings ApplicationInsightsAgent_EXTENSION_VERSION="~2"
az webapp config appsettings set -g $ResourceGroupName -n $WebAppName --settings XDT_MicrosoftApplicationInsights_Mode="disabled"
az webapp config appsettings set -g $ResourceGroupName -n $WebAppName --settings ANCM_ADDITIONAL_ERROR_PAGE_LINK="https://$($WebAppName).scm.azurewebsites.net/detectors?type=tools&&name=eventviewer"

# These app settings are specific to application insights
az webapp config appsettings set -g $ResourceGroupName -n $WebAppName --settings APPINSIGHTS_INSTRUMENTATIONKEY="$($ApplicationInsightsObject.instrumentationKey)"
az webapp config appsettings set -g $ResourceGroupName -n $WebAppName --settings APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$($ApplicationInsightsObject.instrumentationKey)"

# Create app registration
$App = (az ad app create `
        --display-name $WebAppName `
        --identifier-uris "https://$($WebAppName).azurewebsites.net" `
        --reply-urls  "https://$($WebAppName).azurewebsites.net/.auth/login/aad/callback" `
        --homepage "https://$($WebAppName).azurewebsites.net")

$AppObject = $App | ConvertFrom-Json;

# Get service principal
$ServicePrincipal = (az ad sp show --id $AppObject.appId)

If (!$ServicePrincipal) {
    # Create service principal for the app registration
    az ad sp create --id $AppObject.appId
}

# Get app permissions
$AppPermissions = (az ad app permission list --id $AppObject.appId --query "[?resourceAppId=='00000002-0000-0000-c000-000000000000'].resourceAccess[].id")

$AppPermissionsObject = $AppPermissions | ConvertFrom-Json;

$ActiveDirectoryApiId = "00000002-0000-0000-c000-000000000000"
$UserReadScopeId = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"

If (!$AppPermissionsObject -or !$AppPermissionsObject.Contains($UserReadScope)) {
    # Create the api permission User.Read that is required to sign in the user
    az ad app permission add --id $AppObject.appId --api $ActiveDirectoryApiId --api-permissions "$($UserReadScopeId)=Scope"
}

# Get the app registration
$AzAdApplication = Get-AzADApplication -DisplayName $WebAppName

# Generate a password that will be used for the client secret
$Password = ([char[]]([char]65..[char]90) + ([char[]]([char]97..[char]122)) + 0..9 | Sort-Object { Get-Random })[0..30] + ("!=") -Join ""

# Add or append the client secret to the app registration
az ad app credential reset --id $AzAdApplication.ObjectId --password $Password --end-date "12/31/2299"

# Get the account so we can access the tenantId
$Account = (az account show)

# Convert the account to an object so we can easily work with the properties
$AccountObject = $Account | ConvertFrom-Json

# Update the web app authentication and enabled it
az webapp auth update -n $WebAppName -g $ResourceGroupName --enabled true --action LoginWithAzureActiveDirectory --aad-client-id $AzAdApplication.ApplicationId --aad-client-secret $Password --aad-allowed-token-audiences "https://$($WebAppName).azurewebsites.net" --aad-token-issuer-url "https://sts.windows.net/$($AccountObject.tenantId)/"