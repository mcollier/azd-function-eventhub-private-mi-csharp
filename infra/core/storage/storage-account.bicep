param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([
  'Cool'
  'Hot'
  'Premium' ])
param accessTier string = 'Hot'
param allowBlobPublicAccess bool = true
param allowCrossTenantReplication bool = true
param allowSharedKeyAccess bool = true
param containers array = []
param defaultToOAuthAuthentication bool = false
param deleteRetentionPolicy object = {}
@allowed([ 'AzureDnsZone', 'Standard' ])
param dnsEndpointType string = 'Standard'
param kind string = 'StorageV2'
param minimumTlsVersion string = 'TLS1_2'
param networkAcls object = {
  bypass: isBehindVirutalNetwork ? 'None' : 'AzureServices'
  defaultAction: isBehindVirutalNetwork ? 'Deny' : 'Allow'
}
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = isBehindVirutalNetwork ? 'Disabled' : 'Enabled'
param sku object = { name: 'Standard_LRS' }

//NEW
param isBehindVirutalNetwork bool = false
param virtualNetworkName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''

var storageServices = [ 'table', 'blob', 'queue', 'file' ]

// NEW
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (isBehindVirutalNetwork) {
  name: virtualNetworkName

  resource subnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  sku: sku
  properties: {
    accessTier: accessTier
    allowBlobPublicAccess: allowBlobPublicAccess
    allowCrossTenantReplication: allowCrossTenantReplication
    allowSharedKeyAccess: allowSharedKeyAccess
    defaultToOAuthAuthentication: defaultToOAuthAuthentication
    dnsEndpointType: dnsEndpointType
    minimumTlsVersion: minimumTlsVersion
    networkAcls: networkAcls
    publicNetworkAccess: publicNetworkAccess
  }

  resource blobServices 'blobServices' = if (!empty(containers)) {
    name: 'default'
    properties: {
      deleteRetentionPolicy: deleteRetentionPolicy
    }
    resource container 'containers' = [for container in containers: {
      name: container.name
      properties: {
        publicAccess: contains(container, 'publicAccess') ? container.publicAccess : 'None'
      }
    }]
  }
}

// TODO: CONFIRM IF THE ARRAY USAGE AND INDEXING BELOW IS CORRECT. WHAT PROBLEMS AM I CREATING FOR MYSELF?
// NEW - private endpoints
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = [for svc in storageServices: if (isBehindVirutalNetwork) {
  name: 'pe-${svc}'
  location: location
  properties: {
    subnet: {
      id: vnet::subnet.id
      name: virtualNetworkPrivateEndpointSubnetName
    }
    privateLinkServiceConnections: [
      {
        id: storage.id
        name: 'plsc-${svc}'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            svc
          ]
        }
      }
    ]
  }
}]

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = [for svc in storageServices: if (isBehindVirutalNetwork) {
  name: 'privatelink.${svc}.${environment().suffixes.storage}'
  location: 'Global'
}]

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = [for (svc, i) in storageServices: if (isBehindVirutalNetwork) {
  parent: storagePrivateEndpoint[i]
  name: 'dnsZoneGroup-${svc}'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateDnsZone[i].id
        }
      }
    ]
  }
}]

module dnsZoneLink '../networking/dns-zone-vnet-mapping.bicep' = [for (svc, i) in storageServices: if (isBehindVirutalNetwork) {
  name: 'privatelink-${svc}-vnet-link'
  params: {
    privateDnsZoneName: privateDnsZone[i].name
    vnetId: vnet.id
    vnetLinkName: 'vnet-${svc}-link'
  }
}]

output name string = storage.name
output primaryEndpoints object = storage.properties.primaryEndpoints