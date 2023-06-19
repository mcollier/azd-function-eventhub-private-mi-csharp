targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

var serviceName = 'event-consumer-func'

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// TODO: These variable names seem long . . . shorten?
var virtualNetworkAddressSpacePrefix = '10.1.0.0/16'
var virtualNeworkIntegrationSubnetAddressSpacePrefix = '10.1.1.0/24'
var virtualNetworkPrivateEndpointSubnetAddressSpacePrefix = '10.1.2.0/24'

var virtualNetworkName = '${abbrs.networkVirtualNetworks}${resourceToken}'
var virtualNetworkIntegrationSubnetName = '${abbrs.networkVirtualNetworksSubnets}-${resourceToken}-int'
var virtualNetworkPrivateEndpointSubnetName = '${abbrs.networkVirtualNetworksSubnets}-${resourceToken}-pe'

var eventHubConnectionStringSecretName = 'EventHubConnectionString'
var eventHubConsumerGroupName = 'widgetfunctionconsumergroup'

var useVirtualNetwork = true

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module function 'app/function.bicep' = {
  name: serviceName
  scope: rg
  params: {
    name: serviceName
    location: location
    tags: tags
    serviceName: serviceName
    planName: '${abbrs.webServerFarms}${resourceToken}'
    functionAppName: '${abbrs.webSitesFunctions}${resourceToken}'
    applicationInsightsName: appInsights.outputs.name
    eventHubConnectionStringSecretName: eventHubConnectionStringSecretName
    eventHubConsumerGroupName: eventHubConsumerGroupName
    eventHubName: eventHub.outputs.EventHubName
    eventHubNamespaceName: eventHubNamespace.outputs.eventHubNamespaceName
    keyVaultName: keyVault.outputs.name
    storageAccountName: storage.outputs.name
    virtualNetworkIntegrationSubnetName: virtualNetworkIntegrationSubnetName
    virtualNetworkPrivateEndpointSubnetName: virtualNetworkPrivateEndpointSubnetName
    virtualNetworkName: vnet.outputs.virtualNetworkName
  }
}

module storage './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags

    // New
    isBehindVirutalNetwork: true
    virtualNetworkName: vnet.outputs.virtualNetworkName
    virtualNetworkPrivateEndpointSubnetName: virtualNetworkPrivateEndpointSubnetName
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

// TODO: Configure vnet
module keyVault 'core/security/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
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

    keyVaultName: keyVault.outputs.name
    secretName: eventHubConnectionStringSecretName

    isBehindVirutalNetwork: true
    virtualNetworkName: vnet.outputs.virtualNetworkName
    virtualNetworkPrivateEndpointSubnetName: virtualNetworkPrivateEndpointSubnetName
  }
}

module eventHub './core/messaging/event-hub.bicep' = {
  name: 'eventHub'
  scope: rg
  params: {
    name: '${abbrs.eventHubNamespacesEventHubs}widget'
    eventHubNamespaceName: eventHubNamespace.outputs.eventHubNamespaceName
    consumerGroupName: 'WidgetFunctionConsumerGroup'
  }
}

module vnet './core/networking/virtual-network.bicep' = if (useVirtualNetwork) {
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
        properties: {
          addressPrefix: virtualNeworkIntegrationSubnetAddressSpacePrefix
          // networkSecurityGroup: {}

          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: virtualNetworkPrivateEndpointSubnetName
        properties: {
          addressPrefix: virtualNetworkPrivateEndpointSubnetAddressSpacePrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}
