param name string
param location string = resourceGroup().location
param tags object = {}

param functionAppPlanName string
param functionAppName string
param storageAccountName string
param applicationInsightsName string
param eventHubNamespaceName string
param eventHubName string
param eventHubConsumerGroupName string
param keyVaultName string
param isStorageAccountPrivate bool = false
param isVirtualNetworkIntegrated bool = false
param isBehindVirtualNetwork bool = false
param vnetRouteAllEnabled bool = false
param virtualNetworkName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''
param virtualNetworkIntegrationSubnetName string = ''

param userAssignedIdentityName string

var useVirtualNetwork = isBehindVirtualNetwork || isVirtualNetworkIntegrated

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

module functionPlan '../core/host/functionplan.bicep' = {
  name: 'plan-${name}'
  params: {
    location: location
    tags: tags
    name: functionAppPlanName
    planSku: 'EP1'
  }
}

// TODO: Get a better name for this module.
module function '../core/host/functions2.bicep' = {
  name: 'func-${name}'
  params: {
    location: location
    tags: union(tags, { 'azd-service-name': name })
    appServicePlanId: functionPlan.outputs.planId
    name: functionAppName
    runtimeName: 'dotnet'
    runtimeVersion: '6.0'
    storageAccountName: storage.name
    isStorageAccountPrivate: isStorageAccountPrivate
    userAssignedIdentityName: userAssignedIdentityName
    applicationInsightsName: appInsights.name
    extensionVersion: '~4'
    keyVaultName: keyVault.name
    kind: 'functionapp'
    enableOryxBuild: false
    scmDoBuildDuringDeployment: false
    functionsRuntimeScaleMonitoringEnabled: isVirtualNetworkIntegrated ? true : false
    vnetRouteAllEnabled: vnetRouteAllEnabled
    isBehindVirtualNetwork: isBehindVirtualNetwork
    isVirtualNetworkIntegrated: isVirtualNetworkIntegrated
    virtualNetworkName: useVirtualNetwork ? vnet.name : ''
    virtualNetworkIntegrationSubnetName: isVirtualNetworkIntegrated ? vnet::integrationSubnet.name : ''
    virtualNetworkPrivateEndpointSubnetName: isBehindVirtualNetwork ? vnet::privateEndpointSubnet.name : ''

    appSettings: {
      EventHubConnection__fullyQualifiedNamespace: '${eventHubNamespace.name}.servicebus.windows.net'
      EventHubConnection__clientId: uami.properties.clientId
      EventHubConnection__credential: 'managedidentity'
      EventHubName: eventHubNamespace::eventHub.name
      EventHubConsumerGroup: eventHubNamespace::eventHub::consumerGroup.name
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' existing = {
  name: eventHubNamespaceName

  resource eventHub 'eventhubs' existing = {
    name: eventHubName

    resource consumerGroup 'consumergroups' existing = {
      name: eventHubConsumerGroupName
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (useVirtualNetwork) {
  name: virtualNetworkName

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }

  resource integrationSubnet 'subnets' existing = {
    name: virtualNetworkIntegrationSubnetName
  }
}
