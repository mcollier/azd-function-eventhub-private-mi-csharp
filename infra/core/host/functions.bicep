param name string
param location string = resourceGroup().location
param tags object = {}

// Reference Properties
param applicationInsightsName string = ''
param appServicePlanId string
param keyVaultName string = ''
param managedIdentity bool = !empty(keyVaultName)
param storageAccountName string

// NEW - These are incorrect for FUNCTIONS_WORKER_RUNTIME (https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings#functions_worker_runtime)
// dotnetcore is not a valid value for FUNCTIONS_WORKER_RUNTIME
// Runtime Properties
@allowed([
  'dotnet', 'dotnetcore', 'dotnet-isolated', 'node', 'python', 'java', 'powershell', 'custom'
])
param runtimeName string

//NEW
@allowed([
  'dotnet', 'dotnetcore', 'dotnet-isolated', 'node', 'python', 'java', 'powershell', 'custom'
])
param functionsWorkerRuntime string
param runtimeNameAndVersion string = '${runtimeName}|${runtimeVersion}'
param runtimeVersion string

// Function Settings
@allowed([
  '~4', '~3', '~2', '~1'
])
param extensionVersion string = '~4'

// Microsoft.Web/sites Properties
@allowed([ 'functionapp', 'functionapp,linux' ])
param kind string = 'functionapp,linux'

// Microsoft.Web/sites/config
param allowedOrigins array = []
param alwaysOn bool = true
param appCommandLine string = ''
param appSettings object = {}
param clientAffinityEnabled bool = false
param enableOryxBuild bool = contains(kind, 'linux')
param functionAppScaleLimit int = -1
param linuxFxVersion string = runtimeNameAndVersion
param minimumElasticInstanceCount int = -1
param numberOfWorkers int = -1
param scmDoBuildDuringDeployment bool = true
param use32BitWorkerProcess bool = false

// NEW
param vnetRouteAllEnabled bool = false
param functionsRuntimeScaleMonitoringEnabled bool = false
param virtualNetworkName string = ''
param virtualNetworkIntegrationSubnetName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''
// param isStorageAccountPrivate bool = false
// param isVirtualNetworkIntegrated bool = false
param isBehindVirtualNetwork bool = false
param userAssignedIdentityName string = ''
param creationTimeConfigurationSettings array = []

// var useVirtualNetwork = isBehindVirtualNetwork || isVirtualNetworkIntegrated
// var functionWebsiteAzureFileConnectionStringSecretName = 'AzureFunctionContentAzureFileConnectionStringSecret'

//NEW
// TODO: Configurable?
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!empty(userAssignedIdentityName)) {
  name: userAssignedIdentityName
}

//NEW
//if (useVirtualNetwork) {
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (!empty(virtualNetworkName)) {
  name: virtualNetworkName

  resource integrationSubnet 'subnets' existing = {
    name: virtualNetworkIntegrationSubnetName
  }

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

module functions 'appservice.bicep' = {
  name: '${name}-functions'
  params: {
    name: name
    location: location
    tags: tags
    allowedOrigins: allowedOrigins
    alwaysOn: alwaysOn
    appCommandLine: appCommandLine
    applicationInsightsName: applicationInsightsName
    appServicePlanId: appServicePlanId
    appSettings: union(appSettings, {
        AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        FUNCTIONS_EXTENSION_VERSION: extensionVersion
        FUNCTIONS_WORKER_RUNTIME: functionsWorkerRuntime
      })
    clientAffinityEnabled: clientAffinityEnabled
    enableOryxBuild: enableOryxBuild
    functionAppScaleLimit: functionAppScaleLimit
    keyVaultName: keyVaultName
    kind: kind
    linuxFxVersion: linuxFxVersion
    managedIdentity: managedIdentity
    minimumElasticInstanceCount: minimumElasticInstanceCount
    numberOfWorkers: numberOfWorkers
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    runtimeNameAndVersion: runtimeNameAndVersion
    scmDoBuildDuringDeployment: scmDoBuildDuringDeployment
    use32BitWorkerProcess: use32BitWorkerProcess

    //NEW
    // functionsExtensionVersion: extensionVersion
    virtualNetworkSubnetId: empty(virtualNetworkName) ? '' : vnet::integrationSubnet.id
    keyVaultReferenceIdentity: empty(userAssignedIdentityName) ? '' : uami.id
    vnetRouteAllEnabled: vnetRouteAllEnabled
    functionsRuntimeScaleMonitoringEnabled: functionsRuntimeScaleMonitoringEnabled
    creationTimeConfigurationSettings: creationTimeConfigurationSettings
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: storageAccountName
}

resource appServicePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = if (isBehindVirtualNetwork) {
  name: 'pe-${name}-site'
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${name}-site'
        properties: {
          privateLinkServiceId: functions.outputs.id //function.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }

  resource zoneGroup 'privateDnsZoneGroups' = {
    name: 'appServicePrivateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: appServicePrivateDnsZone.id
          }
        }
      ]
    }
  }
}

resource appServicePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (isBehindVirtualNetwork) {
  name: 'privatelink.azurewebsites.net'
  location: 'Global'
}

module appServiceDnsZoneLink '../networking/dns-zone-vnet-mapping.bicep' = if (isBehindVirtualNetwork) {
  name: 'privatelink-appservice-vnet-link'
  params: {
    privateDnsZoneName: appServicePrivateDnsZone.name
    vnetId: vnet.id
    vnetLinkName: '${vnet.name}-link'
  }
}

output identityPrincipalId string = managedIdentity ? functions.outputs.identityPrincipalId : ''
output name string = functions.outputs.name
output uri string = functions.outputs.uri
output id string = functions.outputs.id
