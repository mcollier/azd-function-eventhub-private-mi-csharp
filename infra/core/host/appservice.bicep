param name string
param location string = resourceGroup().location
param tags object = {}

// Reference Properties
param applicationInsightsName string = ''
param appServicePlanId string
param keyVaultName string = ''
param managedIdentity bool = !empty(keyVaultName)

// Runtime Properties
@allowed([
  'dotnet', 'dotnetcore', 'dotnet-isolated', 'node', 'python', 'java', 'powershell', 'custom'
])
param runtimeName string
param runtimeNameAndVersion string = '${runtimeName}|${runtimeVersion}'
param runtimeVersion string

// Microsoft.Web/sites Properties
param kind string = 'app,linux'

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
param scmDoBuildDuringDeployment bool = false
param use32BitWorkerProcess bool = false
param ftpsState string = 'FtpsOnly'
param healthCheckPath string = ''

// NEW
param virtualNetworkName string = ''
param virtualNetworkIntegrationSubnetName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''
param virtualNetworkRouteAllEnabled bool = false
param functionsRuntimeScaleMonitoringEnabled bool = false
param isVirtualNetworkIntegrated bool = false
param isBehindVirutalNetwork bool = false

var useVirtualNetwork = isBehindVirutalNetwork || isBehindVirutalNetwork

resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  properties: {
    serverFarmId: appServicePlanId

    //NEW
    virtualNetworkSubnetId: isVirtualNetworkIntegrated ? vnet::integrationSubnet.id : null

    siteConfig: {
      // NEW
      vnetRouteAllEnabled: isVirtualNetworkIntegrated ? virtualNetworkRouteAllEnabled : false
      functionsRuntimeScaleMonitoringEnabled: functionsRuntimeScaleMonitoringEnabled

      linuxFxVersion: linuxFxVersion
      alwaysOn: alwaysOn
      ftpsState: ftpsState
      minTlsVersion: '1.2'
      appCommandLine: appCommandLine
      numberOfWorkers: numberOfWorkers != -1 ? numberOfWorkers : null
      minimumElasticInstanceCount: minimumElasticInstanceCount != -1 ? minimumElasticInstanceCount : null
      use32BitWorkerProcess: use32BitWorkerProcess
      functionAppScaleLimit: functionAppScaleLimit != -1 ? functionAppScaleLimit : null
      healthCheckPath: healthCheckPath
      cors: {
        allowedOrigins: union([ 'https://portal.azure.com', 'https://ms.portal.azure.com' ], allowedOrigins)
      }

      // TODO: Ask Jon G. about this.  My understanding is that not setting FUNCTIONS_EXTENSION_VERSION at creation time results in a Functions v1 (~1) being created.
      // That is problematic because the controller checks the function version to ensure runtime scale monitoring is supported.  If runtime is not >= 2, the controller
      // fails the deployment.
      // Setting the extension version in the 'config' block only will result in a v1 function being created initially and then updated to v3/4 when the config is set.
      // That creates a restart of the function app.
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
      ]
    }
    clientAffinityEnabled: clientAffinityEnabled
    httpsOnly: true
  }

  identity: { type: managedIdentity ? 'SystemAssigned' : 'None' }

  resource configLogs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: { fileSystem: { level: 'Verbose' } }
      detailedErrorMessages: { enabled: true }
      failedRequestsTracing: { enabled: true }
      httpLogs: { fileSystem: { enabled: true, retentionInDays: 1, retentionInMb: 35 } }
    }
  }

  resource basicPublishingCredentialsPoliciesFtp 'basicPublishingCredentialsPolicies' = {
    name: 'ftp'
    location: location
    properties: {
      allow: false
    }
  }

  resource basicPublishingCredentialsPoliciesScm 'basicPublishingCredentialsPolicies' = {
    name: 'scm'
    location: location
    properties: {
      allow: false
    }
  }
}

module config 'appservice-appsettings.bicep' = if (!empty(appSettings)) {
  name: '${name}-appSettings'
  params: {
    name: appService.name
    appSettings: union(appSettings,
      {
        SCM_DO_BUILD_DURING_DEPLOYMENT: string(scmDoBuildDuringDeployment)
        ENABLE_ORYX_BUILD: string(enableOryxBuild)
      },
      !empty(applicationInsightsName) ? { APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString } : {},
      !empty(keyVaultName) ? { AZURE_KEY_VAULT_ENDPOINT: keyVault.properties.vaultUri } : {})
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = if (!(empty(keyVaultName))) {
  name: keyVaultName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!empty(applicationInsightsName)) {
  name: applicationInsightsName
}

// NEW
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (useVirtualNetwork) {
  name: virtualNetworkName

  resource integrationSubnet 'subnets' existing = {
    name: virtualNetworkIntegrationSubnetName
  }

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

resource appServicePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = if (isBehindVirutalNetwork) {
  name: 'pe-${appService.name}-site'
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${appService.name}-site'
        properties: {
          privateLinkServiceId: appService.id
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

resource appServicePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (isBehindVirutalNetwork) {
  name: 'privatelink.azurewebsites.net'
  location: 'Global'
}

module appServiceDnsZoneLink '../networking/dns-zone-vnet-mapping.bicep' = if (isBehindVirutalNetwork) {
  name: 'privatelink-appservice-vnet-link'
  params: {
    privateDnsZoneName: appServicePrivateDnsZone.name
    vnetId: vnet.id
    vnetLinkName: '${vnet.name}-link'
  }
}

output identityPrincipalId string = managedIdentity ? appService.identity.principalId : ''
output name string = appService.name
output uri string = 'https://${appService.properties.defaultHostName}'
