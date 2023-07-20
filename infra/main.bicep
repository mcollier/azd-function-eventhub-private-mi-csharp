targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param useVirtualNetworkIntegration bool = false
param useVirtualNetworkPrivateEndpoint bool = false

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// var useVirtualNetwork = useVirtualNetworkIntegration
var virtualNetworkAddressSpacePrefix = '10.1.0.0/16'
var virtualNeworkIntegrationSubnetAddressSpacePrefix = '10.1.1.0/24'
var virtualNetworkPrivateEndpointSubnetAddressSpacePrefix = '10.1.2.0/24'
var virtualNetworkName = '${abbrs.networkVirtualNetworks}${resourceToken}'
var virtualNetworkIntegrationSubnetName = '${abbrs.networkVirtualNetworksSubnets}${resourceToken}-int'
var virtualNetworkPrivateEndpointSubnetName = '${abbrs.networkVirtualNetworksSubnets}${resourceToken}-pe'

var eventHubConsumerGroupName = 'widgetfunctionconsumergroup'
var functionAppName = '${abbrs.webSitesFunctions}${resourceToken}'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

@description('This is the built-in role definition for the Key Vault Secret User role. See https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#key-vault-secrets-user for more information.')
resource keyVaultSecretUserRoleDefintion 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

@description('This is the built-in role definition for the Azure Event Hubs Data Receiver role. See https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#azure-event-hubs-data-receiver for more information.')
resource eventHubDataReceiverUserRoleDefintion 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'
}

resource eventHubDataSenderUserRoleDefintion 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '2b629674-e913-4c01-ae53-ef4638d8f975'
}

@description('This is the built-in role definition for the Azure Storage Blob Data Owner role. See https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-owner for more information.')
resource storageBlobDataOwnerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}

// module userAssignedManagedIdentity './core/security/userAssignedIdentity.bicep' = {
//   name: 'userAssignedManagedIdentity'
//   scope: rg
//   params: {
//     name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
//     location: location
//     tags: tags
//   }
// }

// TODO: Scope to the specific resource (Event Hub, Storage, Key Vault) instead of the resource group.
module storageRoleAssignment 'core/security/role.bicep' = {
  name: 'storageRoleAssignment'
  scope: rg
  params: {
    principalId: eventConsumerFunction.outputs.function_app_identity_principal_id
    roleDefinitionId: storageBlobDataOwnerRoleDefinition.name
    principalType: 'ServicePrincipal'
  }
}

module eventHubReceiverRoleAssignment 'core/security/role.bicep' = {
  name: 'eventHubReceiverRoleAssignment'
  scope: rg
  params: {
    principalId: eventConsumerFunction.outputs.function_app_identity_principal_id
    roleDefinitionId: eventHubDataReceiverUserRoleDefintion.name
    principalType: 'ServicePrincipal'
  }
}

module eventHubSenderRoleAssignment 'core/security/role.bicep' = {
  name: 'eventHubSenderRoleAssignment'
  scope: rg
  params: {
    principalId: eventConsumerFunction.outputs.function_app_identity_principal_id
    roleDefinitionId: eventHubDataSenderUserRoleDefintion.name
    principalType: 'ServicePrincipal'
  }
}

module keyVaultRoleAssignment 'core/security/role.bicep' = {
  name: 'keyVaultRoleAssignment'
  scope: rg
  params: {
    principalId: eventConsumerFunction.outputs.function_app_identity_principal_id
    roleDefinitionId: keyVaultSecretUserRoleDefintion.name
    principalType: 'ServicePrincipal'
  }
}

module logAnalytics './core/monitor/loganalytics.bicep' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

module appInsights './core/monitor/applicationinsights.bicep' = {
  name: 'applicationInsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    tags: tags

    includeDashboard: false
    dashboardName: ''
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    location: location
  }
}

module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags

    fileShares: [
      {
        name: functionAppName
      }
    ]

    useVirtualNetworkPrivateEndpoint: useVirtualNetworkPrivateEndpoint
    virtualNetworkName: useVirtualNetworkPrivateEndpoint ? vnet.outputs.virtualNetworkName : ''
    virtualNetworkPrivateEndpointSubnetName: useVirtualNetworkPrivateEndpoint ? virtualNetworkPrivateEndpointSubnetName : ''
  }
}

module eventHubNamespace './core/messaging/event-hub-namespace.bicep' = {
  name: 'eventHubNamespace'
  scope: rg
  params: {
    name: '${abbrs.eventHubNamespaces}${resourceToken}'
    location: location
    tags: tags

    sku: 'Standard'

    useVirtualNetworkPrivateEndpoint: useVirtualNetworkPrivateEndpoint
    virtualNetworkName: useVirtualNetworkPrivateEndpoint ? vnet.outputs.virtualNetworkName : ''
    virtualNetworkPrivateEndpointSubnetName: useVirtualNetworkPrivateEndpoint ? virtualNetworkPrivateEndpointSubnetName : ''
  }
}

module eventHub './core/messaging/event-hub.bicep' = {
  name: 'eventHub'
  scope: rg
  params: {
    name: '${abbrs.eventHubNamespacesEventHubs}widget'
    eventHubNamespaceName: eventHubNamespace.outputs.eventHubNamespaceName
    consumerGroupName: eventHubConsumerGroupName
  }
}

// TODO: Configure vnet
module keyVault 'core/security/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    enabledForRbacAuthorization: true
  }
}

// TODO: Figure out why putting a conditional on the NSG modules causes this error: "ResourceGroupNotFound: Resource group 'rg-private-function-dev' could not be found."
//  It happens for both NSG modules.
module integrationSubnetNsg 'core/networking/network-security-group.bicep' = if (useVirtualNetworkIntegration || useVirtualNetworkPrivateEndpoint) {
  name: 'integrationSubnetNsg'
  scope: rg
  params: {
    name: '${abbrs.networkNetworkSecurityGroups}${resourceToken}-integration-subnet'
    location: location
  }
}

module privateEndpointSubnetNsg 'core/networking/network-security-group.bicep' = if (useVirtualNetworkIntegration || useVirtualNetworkPrivateEndpoint) {
  name: 'privateEndpointSubnetNsg'
  scope: rg
  params: {
    name: '${abbrs.networkNetworkSecurityGroups}${resourceToken}-private-endpoint-subnet'
    location: location
  }
}

module vnet './core/networking/virtual-network.bicep' = if (useVirtualNetworkIntegration || useVirtualNetworkPrivateEndpoint) {
  name: 'vnet'
  scope: rg
  params: {
    name: virtualNetworkName
    location: location
    tags: tags

    virtualNetworkAddressSpacePrefix: virtualNetworkAddressSpacePrefix

    // TODO: Find a better way to handle subnets. I'm not a fan of this array of object approach (losing Intellisense).
    subnets: [
      {
        name: virtualNetworkIntegrationSubnetName
        addressPrefix: virtualNeworkIntegrationSubnetAddressSpacePrefix
        networkSecurityGroupId: integrationSubnetNsg.outputs.id

        delegations: [
          {
            name: 'delegation'
            properties: {
              serviceName: 'Microsoft.Web/serverFarms'
            }
          }
        ]
      }
      {
        name: virtualNetworkPrivateEndpointSubnetName
        addressPrefix: virtualNetworkPrivateEndpointSubnetAddressSpacePrefix
        networkSecurityGroupId: privateEndpointSubnetNsg.outputs.id
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
  }
}

module eventConsumerFunction 'app/event-consumer-func.bicep' = {
  name: 'event-consumer-function'
  scope: rg
  params: {
    name: 'event-consumer-func'
    location: location
    tags: tags
    functionAppPlanName: '${abbrs.webServerFarms}${resourceToken}'
    functionAppName: functionAppName
    applicationInsightsName: appInsights.outputs.name
    eventHubConsumerGroupName: eventHubConsumerGroupName
    eventHubName: eventHub.outputs.EventHubName
    eventHubNamespaceName: eventHubNamespace.outputs.eventHubNamespaceName
    keyVaultName: keyVault.outputs.name
    storageAccountName: storage.outputs.name
    useVirtualNetworkPrivateEndpoint: useVirtualNetworkPrivateEndpoint
    useVirtualNetworkIntegration: useVirtualNetworkIntegration
    virtualNetworkIntegrationSubnetName: useVirtualNetworkIntegration ? virtualNetworkIntegrationSubnetName : ''
    virtualNetworkPrivateEndpointSubnetName: useVirtualNetworkIntegration ? virtualNetworkPrivateEndpointSubnetName : ''
    virtualNetworkName: useVirtualNetworkIntegration ? vnet.outputs.virtualNetworkName : ''
  }
}
