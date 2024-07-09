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

@description('The role definition ID for the Key Vault role assignment for R/W on Secrets on the vault for User and Passwords.')
param keyVaultRoleDef string = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
param akvName string 


@description('The Bulk Loader function app needs to access the FHIR service. This is the role assignment ID to use.')
param fhirContributorRoleAssignmentId string = '5a1fc7df-4bf1-4951-a576-89034ee01acd'

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

// resource hdsAKV 'Microsoft.KeyVault/vaults@2023-07-01' = {
//   name: akvName
//   location: location
//   properties: {
//     sku: {
//       family: 'A'
//       name: 'standard'
//     }
//     accessPolicies: [
//       {
//         tenantId: subscription().tenantId
//         objectId: fhirAdminOID
//         permissions: {
//           keys: ['all']
//           secrets: ['all']
//           certificates: ['all']
//         }
//       }
//     ]
//     tenantId: subscription().tenantId
//     enableSoftDelete: false
//     enableRbacAuthorization: true
//   }
// }

// output keyVaultName string = hdsAKV.name

// resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid('hdsakveus', 'Microsoft.KeyVault/vaults', resourceGroup().name)
//   scope: hdsAKV
//   properties: {
//     principalId: fhirAdminOID
//     roleDefinitionId: keyVaultRoleDef
//   }
// }

// resource role4DeployingAcct 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid('hdsakveus', 'Microsoft.KeyVault/vaults', resourceGroup().name)
//   scope: hdsAKV
//   properties: {
//     principalId: currentUserId
//     roleDefinitionId: keyVaultRoleDef
//   }
// }

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
