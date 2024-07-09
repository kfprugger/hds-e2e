param akvName string
param location string
param fhirAdminOID string
param currentUserId string
// param currentUserOID string

@description('This is the built-in Key Vault Secret User role. See https://docs.microsoft.com/azure/role-based-access-control/built-in-roles#key-vault-secrets-user')
resource keyVaultSecretOfficerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

resource Akv 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: akvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableSoftDelete: false
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${akvName}', 'Microsoft.KeyVault/vaults', resourceGroup().name, 'roleAssignment')
  
  properties: {
    principalId: fhirAdminOID
    roleDefinitionId: keyVaultSecretOfficerRoleDefinition.id
    principalType: 'Group'
  }
  scope: Akv
}

resource currentUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${akvName}', 'Microsoft.KeyVault/vaults', resourceGroup().name, 'currentUser')
  
  properties: {
    principalId: currentUserId
    roleDefinitionId: keyVaultSecretOfficerRoleDefinition.id
    principalType: 'User'
  }
  scope: Akv
}
