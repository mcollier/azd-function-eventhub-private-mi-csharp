param name string
param location string = resourceGroup().location
param tags object = {}

param planName string
param functionAppName string
param serviceName string
param storageAccountName string
param applicationInsightsName string
param eventHubNamespaceName string
param eventHubName string
param eventHubConsumerGroupName string
param eventHubConnectionStringSecretName string
param keyVaultName string
param virtualNetworkName string
param virtualNetworkPrivateEndpointSubnetName string
param virtualNetworkIntegrationSubnetName string

module appServicePlan '../core/host/appserviceplan.bicep' = {
  name: '${name}-plan-module'
  params: {
    name: planName
    location: location
    tags: tags

    sku: {
      name: 'EP1'
      tier: 'ElasticPremium'
    }
    kind: 'elastic'
  }
}

module function '../core/host/functions.bicep' = {
  name: '${name}-function-module'
  params: {
    name: functionAppName
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })

    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'dotnet'
    runtimeVersion: '6.0'
    storageAccountName: storage.name
    managedIdentity: true
    applicationInsightsName: appInsights.name
    alwaysOn: false

    functionsRuntimeScaleMonitoringEnabled: true
    vnetRouteAllEnabled: true
    isBehindVirutalNetwork: false
    isVirtualNetworkIntegrated: true
    virtualNetworkName: vnet.name
    virtualNetworkIntegrationSubnetName: vnet::integrationSubnet.name
    virtualNetworkPrivateEndpointSubnetName: vnet::privateEndpointSubnet.name

    appSettings: {
      EventHubConnection: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${eventHubConnectionStringSecretName})'
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

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: virtualNetworkName

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }

  resource integrationSubnet 'subnets' existing = {
    name: virtualNetworkIntegrationSubnetName
  }
}

module functionKeyVaultAccess '../core/security/keyvault-access.bicep' = {
  name: 'function-key-vault-access'
  params: {
    keyVaultName: keyVault.name
    principalId: function.outputs.identityPrincipalId
  }
}
