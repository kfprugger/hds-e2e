    # Author:   Joey Brakefield
    # Date:     2024-07-07
    # Resource: hds-e2e/deploy.ps1, hds-e2e/deploy.bicep, hds-e2e/infra.bicep, hds-e2e/akv.bicep
    # Purpose:  This script is used to deploy the entire HDS E2E solution. It creates the necessary resources in Azure, 
    #           including the FHIR Service, Azure Key Vault, Service Principal, and FHIR Loader. 
    #           It also generates synthetic data using Synthea and sends it to the Azure Storage Account 
    #           for the FHIR Loader to process.


# Run PreReqs.ps1 to ensure all necessary tools are installed
.\prereqs.ps1

# Begin the deployment process
## change this to whatever short prefix you'd like. No more than 5 lowercase letters or numbers.
$svcNamingPrefix = "rjb"

## Entra ID Group name of the admins who will have access to the FHIR Service, storage account, and other parts of the infra deployment outside of the current user executing this script.
$fhirAdminEntraGrpName = "sg-fhir-services"
$spnName = "spn-fhir-service"
$currentUserOID = (Get-AzADUser -UserPrincipalName $((Get-AzContext).Account.Id)).id
$tenantId = (Get-AzContext).Tenant.Id

## Create the resource group name, location, and service names
$resourceGroupName = "rg-hdsinfra"
$akvName = "hdsakveus"
$location= 'eastus'
$fhirServiceName = $svcNamingPrefix+"fhir"+$location
$ahdsServiceName = "hltwrk$location"

## Synthea Variables
$syntheticPatientCount = 10
$syntheticHospitals = "true"
$syntheticPractitioners = "true"


# Check for Resource Group. Create if it doesn't exist
if (!(Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
} else {
    "Resource Group $resourceGroupName already exists. Moving on to check for FHIR Service Group."
}

# Check for Cognitive Language Services Account. Change the variable name if it does exist already as it has random characters. This keeps the script idempotent.
if ((Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)) {
    $cogSvcAcctName = (Get-AzCognitiveServicesAccount -ResourceGroupName $resourceGroupName).AccountName
    Write-Host "Cognitive Services"$cogSvcAcctName"already exists. Moving on to check for FHIR Export Storage Account."
} else {
    $cogSvcAcctName = $svcNamingPrefix+"txtcog"+$location+$(Get-Random -Maximum 200)
}
$exportSAExists = $false
$exportSANamePattern = $svcNamingPrefix + "export"
$storageAccounts = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if ($storageAccounts) {
    foreach ($storageAccount in $storageAccounts) {
        if ($storageAccount.StorageAccountName.StartsWith($exportSANamePattern)) {
            $exportSAExists = $true
            
        }
    }
}

# Check for export Storage Account. Create the exportSAName variable if it doesn't exist else use the existing name with random numbers. This keeps the script idempotent.
if ($exportSAExists -eq $false)  {
    $exportSAName = $svcNamingPrefix+"export"+$(Get-Random -Maximum 40)
    Write-Host "Export Storage Account does not exist. Setting up $exportSAName variable."
} else {
    $exportSAName = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName | ? {$_.StorageAccountName -match ($svcNamingPrefix+"export")}).StorageAccountName
    Write-Host "Export Storage Account $exportSAName already exists. Moving on to check for FHIR Service Group."
}

# Check for FHIR Service Group. Create if it doesn't exist
if (!(Get-AzADGroup -DisplayName $fhirAdminEntraGrpName -erroraction SilentlyContinue)) {
    "FHIR Service Group does not exist. Creating it now."
    $fhirAdminEntraGrp = New-AzADGroup -DisplayName $fhirAdminEntraGrpName  -MailNickname $fhirAdminEntraGrpName -Description "FHIR Service Administrators Group" 
    New-AzADGroupOwner -GroupId $fhirAdminEntraGrp.Id -OwnerId $currentUserOID

} else {
    "FHIR Service Group already exists. Moving on to check for Azure Key Vault."
    $fhirAdminEntraGrp = Get-AzADGroup -DisplayName $fhirAdminEntraGrpName
}

# check for Key Vault. Create if it doesn't exist
if (!(Get-AzKeyVault -VaultName $akvName)) {
    $akvdep = New-AzResourceGroupDeployment -Name "akv$(Get-Random)" -ResourceGroupName $resourceGroupName -Verbose -TemplateFile ".\akv.bicep" -TemplateParameterObject @{
        akvName=$akvName
        location=$location
        fhirAdminOID=$fhirAdminEntraGrp.Id
        currentUserId=$currentUserOID} 
        #new-azroleassignment -RoleDefinitionName "Key Vault Secrets Officer" -ObjectId $fhirAdminEntraGrp.Id  -scope $akv.ResourceId
    
    "Key Vault $akvName created successfully. Moving on to check for Service Principal info."
    $akv = Get-AzKeyVault -VaultName $akvName    
} elseif (!(Get-AzKeyVaultSecret -VaultName $akvName -Name "spn-secret")) {
    $akv = Get-AzKeyVault -VaultName $akvName
    }
    else {
    "Key Vault already exists. Moving on to check for Service Principal info."
   
        $akv = Get-AzKeyVault -VaultName $akvName
}



write-host -ForegroundColor Green $akv.VaultName -NoNewline; Write-Host " in place. Checking for Service Principal info."

# Check for Service Principal. Create if it doesn't exist
if (!(Get-AzADServicePrincipal -DisplayName $spnName)){
    Write-Host "Creating Service Prinicpal"
    $spn = New-AzADServicePrincipal -DisplayName $spnName 
    $spnCreds = $spn.PasswordCredentials.SecretText
    Add-AzADGroupMember -MemberObjectId $currentUserOID -TargetGroupObjectId $fhirAdminEntraGrp.Id -ErrorAction SilentlyContinue
    Set-AzKeyVaultSecret -VaultName $akvName -Name "spn-secret" -SecretValue $(ConvertTo-SecureString -AsPlainText $spnCreds)
    Set-AzKeyVaultSecret -VaultName $akvName -Name "spn-app-id" -SecretValue $(ConvertTo-SecureString -AsPlainText $spn.AppId)

    if (!($(Get-AzADGroupMember  -GroupObjectId $fhirAdminEntraGrp.Id).Id -eq $currentUserOID)){
        Add-AzADGroupMember -MemberObjectId @($currentUserOID) -TargetGroupObjectId $fhirAdminEntraGrp.Id -ErrorAction SilentlyContinue
    }
    if (!($(Get-AzADGroupMember  -GroupObjectId $fhirAdminEntraGrp.Id).Id -eq $spn.Id)){
        Add-AzADGroupMember -MemberObjectId @($spn.Id) -TargetGroupObjectId $fhirAdminEntraGrp.Id  -ErrorAction SilentlyContinue
    }
} else {
    $spn = Get-AzADServicePrincipal -DisplayName $spnName
    $spnCreds = Get-AzKeyVaultSecret -VaultName $akvName -Name "spn-secret" -ErrorAction Break
    if (!($(Get-AzADGroupMember  -GroupObjectId $fhirAdminEntraGrp.Id).Id -eq $currentUserOID)){
        Add-AzADGroupMember -MemberObjectId @($currentUserOID) -TargetGroupObjectId $fhirAdminEntraGrp.Id
    } else {
        "$($(Get-AzContext).Account.Id) already part of the $fhirAdminEntraGrpName group. Moving on to check for Service Principal."
    }
    if (!($(Get-AzADGroupMember  -GroupObjectId $fhirAdminEntraGrp.Id).Id -eq $spn.Id)){
        Add-AzADGroupMember -MemberObjectId @($spn.Id) -TargetGroupObjectId $fhirAdminEntraGrp.Id -ErrorAction SilentlyContinue
        
    } else {
        "Service Principal already part of the $fhirAdminEntraGrpName group. Moving on to for Primary FHIR Service deployment."
    }
}


$fhirAdminOID = $fhirAdminEntraGrp.Id

$paramHashTable = @{fhirAdminOID=$fhirAdminOID 
currentUserId=$currentUserOID
akvName = $akvName
fhirServiceName=$fhirServiceName
ahdsServiceName=$ahdsServiceName
cogSvcAcctName=$cogSvcAcctName
location=$location
exportSAName=$exportSAName}

# Set-AzMarketplaceTerms -Name healthcare-data-solutions-on-microsoft-fabric -Publisher ics-solutioncenter -Product healthcare-data-solutions-on-microsoft-fabric -Accept

$result = New-AzResourceGroupDeployment -Name "fhirkindlin" -ResourceGroupName $resourceGroupName -TemplateFile ".\infra.bicep" -TemplateParameterObject $paramHashTable -Verbose

# Get the FHIR Service URI
foreach ($key in $result.Outputs.keys) {
    if ($key -eq "fhirServiceUri") {
        $fhirServiceUri = $result.Outputs[$key].value
    } elseif ($key -eq "keyVaultName") {
        $akvName = $result.Outputs[$key].value
    } elseif ($key -eq "fhirServiceId") {
        $fhirServiceId = $result.Outputs[$key].value
    }
}
"New FHIR Service URI is: $fhirServiceUri"
"New Azure Key Vault Name is: $akvName"





# Synthea Synthetic Creation and FHIR Service Population
## create failure folder if it does not exist
if (-not (Test-Path $PWD\output\failed)) {
    New-Item -ItemType Directory -Path $PWD\output\failed
}

## create a success folder if it does not exist
if (-not (Test-Path $PWD\output\success)) {
    New-Item -ItemType Directory -Path $PWD\output\success
}

## Check if the FHIR Service is up and running
$token = (Get-AzAccessToken -ResourceUrl $fhirServiceUri).Token
$headers = @{Authorization="Bearer $token"}
if ($(Invoke-WebRequest -Method GET -Headers $headers -Uri "$fhirServiceUri/Patient").BaseResponse.StatusCode -eq 200){
    Write-Host "FHIR Service is up and running. Proceeding with Synthea Synthetic Data Creation and Population."
} else {
    Write-Host "FHIR Service is not up and running. Please check the service and try again."
    break
}

# Create the FHIR Loader Azure Deployment
$params4FHIRLoader = @{
    prefix="rjb"
    fhirType="FhirService"
    location=$location
    fhirFullServiceName=$ahdsServiceName+"/"+$fhirServiceName
    fhirServiceId=$fhirServiceId
    appServiceSize="B1" 
    fhirAdminOID=$fhirAdminOID
    currentUserId=$currentUserOID
    fhirServiceUri=$fhirServiceUri
}



## Uncomment when .bicep files are corrected to ensure latest fhir-loader deployment. This repo is under active development
# if (!(Test-Path .\fhir-loader)){
#     Write-Host "Cloning fhir-loader repo from Microsoft into local dir"
#     git clone https://github.com/microsoft/fhir-loader.git
# }
$fhirLoaderDeployment = New-AzResourceGroupDeployment -Name "fhirLoader" -ResourceGroupName $resourceGroupName -TemplateFile ".\fhir-loader\scripts\fhirBulkImport.bicep" -TemplateParameterObject $params4FHIRLoader -Verbose


# Grab the FHIR Loader variables from the deployment
foreach ($key in $fhirLoaderDeployment.Outputs.Keys) {
    $value = $fhirLoaderDeployment.Outputs[$key].Value
    Set-Variable -Name $key -Value $value
}


## Run Synthea to generate synthetic data
"Generating Synthetic Data from Synthea. This may take a while if this is your first time running this."
docker run --rm -v $PWD/output:/output --name synthea-docker intersystemsdc/irisdemo-base-synthea:version-1.3.4 -p $syntheticPatientCount `
-s $(Get-Random) Tennessee Nashville `
--exporter.fhir.export=true `
--exporter.hospital.fhir.export=$syntheticHospitals `
--exporter.practitioner.fhir.export=$syntheticPractitioners




# Send the synthetic data to the Azure Storage Account for the FHIR Loader to process new files you just generated.
$fhirSA = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
$ctx = $fhirSA.Context
$containerName = "bundles"

foreach ($file in Get-ChildItem $PWD\output\fhir\*.json) {
    $file.FullName
    Write-Host "Sending $($file.Name) to the Azure Storage Account for the FHIR Loader to process using Entra ID AuthZ."
    azcopy copy $file.FullName "https://$storageAccountName.blob.core.windows.net/bundles/$($file.Name)" --
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully sent $($file.Name) to the Azure Storage Account for the FHIR Loader to process."
        Move-Item $file.FullName $PWD\output\success
        $success += 1
    } else {
        Write-Host "Failed to send $($file.Name) to the Azure Storage Account for the FHIR Loader to process."
        Move-Item $file.FullName $PWD\output\failed
    }
}

Write-Host "Synthetic data bundles numbering $success have been generated and sent to the Azure Storage Account for the FHIR Loader to process. The FHIR Loader will now process the data and send it to the FHIR Service."


$token = (Get-AzAccessToken -ResourceUrl $fhirServiceUri).Token
$headers = @{Authorization="Bearer $token"; "Accept"="application/fhir+json"; "Prefer"="respond-async"}


Invoke-WebRequest -Method GET -Headers $headers -Uri "$fhirServiceUri/`$export?_container=ndjsonexport" -ContentType "application/json"  