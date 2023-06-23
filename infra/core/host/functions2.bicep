param name string
param location string = resourceGroup().location
param tags object = {}

// Reference Properties
param applicationInsightsName string = ''
param appServicePlanId string
param keyVaultName string = ''
param managedIdentity bool = !empty(keyVaultName)
param storageAccountName string

// Runtime Properties
@allowed([
  'dotnet', 'dotnetcore', 'dotnet-isolated', 'node', 'python', 'java', 'powershell', 'custom'
])
param runtimeName string
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
param appSettings object = {}
param clientAffinityEnabled bool = false
param enableOryxBuild bool = contains(kind, 'linux')
param functionAppScaleLimit int = -1
param linuxFxVersion string = runtimeNameAndVersion
param minimumElasticInstanceCount int = -1
param numberOfWorkers int = -1
param scmDoBuildDuringDeployment bool = true
param use32BitWorkerProcess bool = false
// param runFromPackage string = '1'

// NEW
param vnetRouteAllEnabled bool = false
param functionsRuntimeScaleMonitoringEnabled bool = false

// Microsoft.Network/virtualNetworks properties
param virtualNetworkName string = ''
param virtualNetworkIntegrationSubnetName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''
param isStorageAccountPrivate bool = false
param isVirtualNetworkIntegrated bool = false
param isBehindVirtualNetwork bool = false

param userAssignedIdentityName string

var useVirtualNetwork = isBehindVirtualNetwork || isVirtualNetworkIntegrated
var functionWebsiteAzureFileConnectionStringSecretName = 'AzureFunctionContentAzureFileConnectionStringSecret'

// TODO: Configurable?
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

resource function 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  identity: {
    // type: managedIdentity ? 'SystemAssigned' : 'None'
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlanId

    //NEW
    virtualNetworkSubnetId: isVirtualNetworkIntegrated ? vnet::integrationSubnet.id : null
    clientAffinityEnabled: clientAffinityEnabled
    httpsOnly: true

    keyVaultReferenceIdentity: uami.id

    siteConfig: {
      vnetRouteAllEnabled: isVirtualNetworkIntegrated ? vnetRouteAllEnabled : false
      functionsRuntimeScaleMonitoringEnabled: functionsRuntimeScaleMonitoringEnabled
      linuxFxVersion: contains(kind, 'linux') ? linuxFxVersion : null
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      numberOfWorkers: numberOfWorkers != -1 ? numberOfWorkers : null
      minimumElasticInstanceCount: minimumElasticInstanceCount != -1 ? minimumElasticInstanceCount : null
      use32BitWorkerProcess: use32BitWorkerProcess
      functionAppScaleLimit: functionAppScaleLimit != -1 ? functionAppScaleLimit : null
      cors: {
        allowedOrigins: union([ 'https://portal.azure.com', 'https://ms.portal.azure.com' ], allowedOrigins)
      }
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: extensionVersion
        }
      ]
    }
  }
}

// TODO: Move this back to the main function resource creation?
module appSettingsConfig 'appservice-appsettings.bicep' = {
  name: '${name}-appSettings'
  params: {
    name: function.name
    appSettings: union(appSettings,
      {
        // Due to https://github.com/Azure/azure-functions-host/issues/7094, setting WEBSITE_CONTENTAZUREFILECONNECTIONSTRING
        // seperate from the initial function resource creation (along with any other non-essential app settings).
        WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${functionWebsiteAzureFileConnectionStringSecretName})'
        WEBSITE_CONTENTSHARE: name
        ENABLE_ORYX_BUILD: string(enableOryxBuild)
        SCM_DO_BUILD_DURING_DEPLOYMENT: string(scmDoBuildDuringDeployment)
        APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
        FUNCTIONS_WORKER_RUNTIME: runtimeName
        FUNCTIONS_EXTENSION_VERSION: extensionVersion
        AzureWebJobsStorage__accountName: storage.name
        AzureWebJobsStorage__credential: 'managedidentity'
        AzureWebJobsStorage__clientId: uami.properties.clientId
        // WEBSITE_RUN_FROM_PACKAGE: runFromPackage
      },
      (isStorageAccountPrivate) ? {
        WEBSITE_CONTENTOVERVNET: 1
        WEBSITE_SKIP_CONTENTSHARE_VALIDATION: 1
      } : {}
    )
  }
}

module functionContentAzureFileConnectionStringSecret '../security/keyvault-secret.bicep' = {
  name: 'functionContentAzureFileConnectionStringSecret'
  params: {
    name: functionWebsiteAzureFileConnectionStringSecretName
    keyVaultName: keyVault.name
    secretValue: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = if (!(empty(keyVaultName))) {
  name: keyVaultName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(applicationInsightsName)) {
  name: applicationInsightsName
}

resource storage 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: storageAccountName
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (useVirtualNetwork) {
  name: virtualNetworkName

  resource integrationSubnet 'subnets' existing = {
    name: virtualNetworkIntegrationSubnetName
  }

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

resource appServicePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = if (isBehindVirtualNetwork) {
  name: 'pe-${function.name}-site'
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${function.name}-site'
        properties: {
          privateLinkServiceId: function.id
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

output name string = function.name
output uri string = 'https://${function.properties.defaultHostName}'

// var virtualNetworkRestrictedAppSettings = [
//   {
//     name: 'WEBSITE_CONTENTOVERVNET'
//     value: 1
//   }
//   {
//     name: 'WEBSITE_SKIP_CONTENTSHARE_VALIDATION'
//     value: 1
//   }
// ]

// appSettings: union(appSettings, [
//     {
//       name: 'AzureWebJobsStorage__accountName'
//       value: storage.name
//     }
//     {
//       name: 'AzureWebJobsStorage__credential'
//       value: 'managedidentity'
//     }
//     {
//       name: 'AzureWebJobsStorage__clientId'
//       value: uami.properties.clientId
//     }
//     {
//       name: 'FUNCTIONS_EXTENSION_VERSION'
//       value: extensionVersion
//     }
//     {
//       name: 'FUNCTIONS_WORKER_RUNTIME'
//       value: runtimeName
//     }
//     {
//       name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
//       value: applicationInsights.properties.ConnectionString
//     }
//     {
//       name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
//       value: string(scmDoBuildDuringDeployment)
//     }
//     {
//       name: 'ENABLE_ORYX_BUILD'
//       value: string(enableOryxBuild)
//     }
//     // {
//     //   name: 'WEBSITE_RUN_FROM_PACKAGE'
//     //   value: runFromPackage
//     // }
//     {
//       name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
//       value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=AzureFunctionContentAzureFileConnectionStringSecret)'
//     }
//     {
//       name: 'WEBSITE_CONTENTSHARE'
//       value: name
//     }
//   ],
//   isStorageAccountPrivate ? virtualNetworkRestrictedAppSettings : []
// )
