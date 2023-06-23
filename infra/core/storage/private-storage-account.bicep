param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([
  'Cool'
  'Hot'
  'Premium' ])
param accessTier string = 'Hot'
param allowBlobPublicAccess bool = false
param allowCrossTenantReplication bool = true
param allowSharedKeyAccess bool = true
param containers array = []
param fileShares array = []
param defaultToOAuthAuthentication bool = false
param deleteRetentionPolicy object = {}
@allowed([ 'AzureDnsZone', 'Standard' ])
param dnsEndpointType string = 'Standard'
param kind string = 'StorageV2'
param minimumTlsVersion string = 'TLS1_2'
param networkAcls object = {
  bypass: 'None'
  defaultAction: 'Deny'
}
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = 'Disabled'
param sku object = { name: 'Standard_LRS' }

param virtualNetworkName string
param virtualNetworkPrivateEndpointSubnetName string

var storageServices = [ 'table', 'blob', 'queue', 'file' ]

module storage 'storage-account.bicep' = {
  name: name
  params: {
    name: name
    location: location
    tags: tags
    fileShares: fileShares
    allowBlobPublicAccess: allowBlobPublicAccess
    containers: containers
    deleteRetentionPolicy: deleteRetentionPolicy
    kind: kind
    minimumTlsVersion: minimumTlsVersion
    sku: sku
    allowCrossTenantReplication: allowCrossTenantReplication
    defaultToOAuthAuthentication: defaultToOAuthAuthentication
    accessTier: accessTier
    allowSharedKeyAccess: allowSharedKeyAccess
    dnsEndpointType: dnsEndpointType
    publicNetworkAccess: publicNetworkAccess
    networkAcls: networkAcls
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: virtualNetworkName

  resource subnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

// TODO: CONFIRM IF THE ARRAY USAGE AND INDEXING BELOW IS CORRECT. WHAT PROBLEMS AM I CREATING FOR MYSELF?
// NEW - private endpoints
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = [for svc in storageServices: {
  name: 'pe-${svc}'
  location: location
  properties: {
    subnet: {
      id: vnet::subnet.id
      name: virtualNetworkPrivateEndpointSubnetName
    }
    privateLinkServiceConnections: [
      {
        id: storage.outputs.id
        name: 'plsc-${svc}'
        properties: {
          privateLinkServiceId: storage.outputs.id
          groupIds: [
            svc
          ]
        }
      }
    ]
  }
}]

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = [for svc in storageServices: {
  name: 'privatelink.${svc}.${environment().suffixes.storage}'
  location: 'Global'
}]

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = [for (svc, i) in storageServices: {
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

module dnsZoneLink '../networking/dns-zone-vnet-mapping.bicep' = [for (svc, i) in storageServices: {
  name: 'privatelink-${svc}-vnet-link'
  params: {
    privateDnsZoneName: privateDnsZone[i].name
    vnetId: vnet.id
    vnetLinkName: 'vnet-${svc}-link'
  }
}]

output name string = storage.name
