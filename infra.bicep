param location string
param fhirServiceName string 
param ahdsServiceName string
param fhirKind string = 'fhir-R4'
// param publisherID string = 'ics-solutioncenter'
// param productID string = 'healthcare-data-solutions-on-microsoft-fabric'
// param planID string = 'healthcare-data-solutions-on-microsoft-fabric'
// param HDSServiceName string = 'hdsinfra'
param fhirAdminOID string 
param cogSvcAcctName string 
param currentUserId string
param exportSAName string
param akvName string 

@description('Static Role ID Storage Blob Data Contributor on storage account')
param storageBlobContributorId string = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'


@description('The Bulk Loader function app needs to access the FHIR service. This is the role assignment ID to use.')
param fhirContributorRoleAssignmentId string = '5a1fc7df-4bf1-4951-a576-89034ee01acd'

@description('The role definition ID for the Storage Blob Data Contributor role assignment.')
resource storageBlobContribRole 'Microsoft.Authorization/roleAssignments@2022-04-01' existing = {
  name: storageBlobContributorId
  scope: subscription()
}

resource healthcareAPIsWorkspace 'Microsoft.HealthcareApis/workspaces@2024-03-31' = {
  name: ahdsServiceName
  location: location
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource fhirService 'Microsoft.HealthcareApis/workspaces/fhirservices@2024-03-31' = {
  parent: healthcareAPIsWorkspace
  name: fhirServiceName
  location: location
  kind: fhirKind
  identity: {
    type: 'SystemAssigned'
  }
  properties:{
    authenticationConfiguration: {
      authority: uri(environment().authentication.loginEndpoint, subscription().tenantId)
      audience: 'https://${ahdsServiceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'
    }
    publicNetworkAccess: 'Enabled'
    exportConfiguration: {
      storageAccountName: exportSA.name
    }
  }
  
}

output fhirServiceUri string = 'https://${healthcareAPIsWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'
output fhirServiceId string = fhirService.id

resource fhirContribRoleID 'Microsoft.Authorization/roleAssignments@2022-04-01' existing = {
  name: fhirContributorRoleAssignmentId
  scope: subscription()
}

resource fhirCurrentUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('fhirCurrentUserAssignment', 'Microsoft.Authorization/roleAssignments', subscription().subscriptionId)
  scope: fhirService
  properties: {
    principalId: currentUserId
    roleDefinitionId: fhirContribRoleID.id
  }
}

resource fhirGroupAdminsAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('fhirGroupAdminsAssignment', 'Microsoft.Authorization/roleAssignments', subscription().subscriptionId)
  scope: fhirService
  properties: {
    principalId: fhirAdminOID
    roleDefinitionId: fhirContribRoleID.id
  }
}

resource cogSvcAcct 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: cogSvcAcctName
  location: location
  kind: 'TextAnalytics'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}


resource hdsAKV 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: akvName
}

resource fhirApiUriSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'fhir-service-uri'
  parent: hdsAKV
  properties: {
    value: 'https://${ahdsServiceName}-${fhirServiceName}.azurehealthcareapis.com'
  }
}

resource exportSA 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: exportSAName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: true
  }

  resource service 'blobServices' = {
    name: 'default'
    resource ndjsoncont 'containers' = {
      name: 'ndjsonexport'
    }
  }
}

@description('Role assignment for the FHIR service to write to the export storage account')
resource storageBlobContribRoleAssignment4FHIR 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('ba92f5b4-2d11-453d-a403-e96b0029c9fe', exportSA.id, fhirService.id)
  scope: exportSA
  properties: {
    roleDefinitionId: storageBlobContribRole.id
    principalId: fhirService.identity.principalId
  }
  
}

@description('Role assignment for the Bulk Loader function app to write to the export storage account')
resource storageBlobContribRoleAssignmentFxn 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('ba92f5b4-2d11-453d-a403-e96b0029c9fe', exportSA.id, currentUserId)
  scope: exportSA
  properties: {
    roleDefinitionId: storageBlobContribRole.id
    principalId: currentUserId
  }
}

@description('Role assignment for the FHIR service Entra ID Group to write to the export storage account')
resource storageBlobContribRoleAssignmentAdmins 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name: guid('ba92f5b4-2d11-453d-a403-e96b0029c9fe', exportSA.id, fhirAdminOID)
    scope: exportSA
    properties: {
      roleDefinitionId: storageBlobContribRole.id
      principalId: fhirAdminOID
    }
}
  



// resource HDSService 'Microsoft.Saas/resources@2018-03-01-beta' = {
//   name: HDSServiceName
//   location: 'global'

//   properties: {   
//     publisherId: publisherID
//     productId: productID
//     SKUId: planID
//     offerId: 'healthcare-data-solutions-on-microsoft-fabric'
//     termId: 'healthcare-data-solutions-on-microsoft-fabric'
//     deployUpdatesOnly: false
//     fhirServerUri: uri(environment().authentication.loginEndpoint, subscription().tenantId)
//     languageServiceName: 'cogSvcAcct.name'
//     exportStartTime: '2023-03-15'
//     location: location
//     term: {
//       endDate: '2022-07-06T00:00:00Z'
//       startDate: '2022-06-06T00:00:00Z'
//       termId: null
//       // termUnit: 'P1M'
//   }
//     paymentChannelType: 'SubscriptionDelegated'
//     storeFront: 'AzurePortal'
//     paymentChannelMetadata: {
//       AzureSubscriptionId: subscription().subscriptionId

//     }
//   }
// }


// resource hdsRG 'Microsoft.Solutions/applications@2021-07-01' = {
//   name: 'hdsrg'
//   location: location
//   kind: 'ServiceCatalog'

//   plan: {
//     name: 'healthcare-data-solutions-on-microsoft-fabric'
//     product: productID
//     publisher: publisherID
//   }
//   properties: {
//     storeFront: 'AzurePortal'
//     // version: '1.0'
//   }

//   // properties: {
//   //   managedResourceGroupId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/hdsrg'
//   //   applicationDefinitionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/hdsrg/providers/Microsoft.Solutions/applications/hdsinfra'
//   //   applicationDefinitionVersion: '1.0'
//   //   planName: 'healthcare-data-solutions-on-microsoft-fabric'
//   //   planPublisher: 'ics-solutioncenter'
//   //   planProduct: 'healthcare-data-solutions-on-microsoft-fabric'
//   //   planVersion: '1.0'
//   //   parameters: {
//   //     fhirServiceName: fhirServiceName
//   //     fhirAdminOID: fhirAdminOID
//   //     cogSvcAcctName: cogSvcAcctName
//   //     tenantID: tenantID
//     // }
//   // }
// }
