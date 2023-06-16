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

var abbrs = loadJsonContent('./bicep/abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

var virtualNetworkName = '${abbrs.networkVirtualNetworks}${resourceToken}'

var behindVnet = true

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module appServicePlan 'bicep/core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    location: location
    name: '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'EP1'
      tier: 'ElasticPremium'
    }
    kind: 'elastic'
    tags: tags
  }
}

module function 'bicep/core/host/functions.bicep' = {
  name: 'function'
  scope: rg
  params: {
    location: location
    name: '${abbrs.webSitesFunctions}${resourceToken}'
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'dotnetcore'
    runtimeVersion: '7.0'
    storageAccountName: storage.outputs.name
    managedIdentity: true
    applicationInsightsName: appInsights.outputs.name
    alwaysOn: false
    tags: tags

    functionsRuntimeScaleMonitoringEnabled: true

    vnetRouteAllEnabled: behindVnet ? true : false
    virtualNetworkName: behindVnet ? virtualNetworkName : ''
    virtualNetworkSubnetName: behindVnet ? 'subnet1' : ''
  }
}

// TODO: Add behindVnet support
module storage 'bicep/core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
  }
}

module logAnalytics 'bicep/core/monitor/loganalytics.bicep' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
  }
}

module appInsights 'bicep/core/monitor/applicationinsights.bicep' = {
  name: 'applicationInsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    includeDashboard: false
    dashboardName: ''
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    location: location
  }
}

// TODO: Create a "behind_vnet" boolean to use for toggeling if services use a vnet and are restricted to a vnet
// https://www.ms-playbook.com/code-with-engineering/developer-experience/toggle-vnet-dev-environment

module vnet 'bicep/core/networking/virtual-network.bicep' = if (behindVnet) {
  name: 'vnet'
  scope: rg
  params: {
    name: virtualNetworkName
    location: location
    virtualNetworkAddressSpacePrefix: '10.1.0.0/16'
    subnets: [
      {
        name: 'subnet1'
        properties: {
          addressPrefix: '10.1.1.0/24'
          // networkSecurityGroup: {}

          // TODO: Set up app service integration
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
    ]
    tags: tags
  }
}
