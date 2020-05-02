param (
    [string]$Tenant
)

If ($Tenant.Trim() -eq "" ) { 
    $Tenant = Read-Host -Prompt "Enter your FIRST part of your tenant name, e.g. if your tenant was microsoft.onmicrosoft.com, just enter microsoft"
}

If ($Tenant.Trim() -eq "" ) { 
    Throw "Tenant is required, either enter as a prompt or provide a value for the -Tenant argument"
}

Connect-AzAccount -Tenant "$($Tenant).onmicrosoft.com"

az login --tenant "$($Tenant).onmicrosoft.com"