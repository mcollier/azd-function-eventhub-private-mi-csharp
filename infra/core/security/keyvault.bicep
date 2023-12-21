param name string
param location string = resourceGroup().location
param tags object = {}

param principalId string = ''

// NEW
param enabledForRbacAuthorization bool = false
param useVirtualNetworkPrivateEndpoint bool = false
param virtualNetworkName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = useVirtualNetworkPrivateEndpoint ? 'Disabled' : 'Enabled'

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: name
  location: location
  tags: tags

  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: enabledForRbacAuthorization
    accessPolicies: !empty(principalId) ? [
      {
        objectId: principalId
        permissions: { secrets: [ 'get', 'list' ] }
        tenantId: subscription().tenantId
      }
    ] : []
    publicNetworkAccess: publicNetworkAccess
  }
}

// NEW
// module privateDnsZone '../networking/private-dns-zone.bicep' = if (useVirtualNetworkPrivateEndpoint) {
//   name: 'keyVaultPrivateDnsZone'
//   params: {
//     dnsZoneLinkName: '${keyVault.name}-dnsZoneLink'
//     dnsZoneName: 'privatelink.vaultcore.azure.net'
//     virtualNetworkName: vnet.name
//   }
// }

// NEW
module privateEndpoint '../networking/private-endpoint.bicep' = if (useVirtualNetworkPrivateEndpoint) {
  name: 'keyVaultPrivateEndpoint'
  params: {
    location: location
    // See https://github.com/Azure/bicep/issues/3990
    // privateDnsZoneId: useVirtualNetworkPrivateEndpoint ? privateDnsZone.outputs.privateDnsZoneId : ''
    privateEndpointName: 'pe-${keyVault.name}'
    privateLinkServiceId: keyVault.id
    subnetId: vnet::privateEndpointSubnet.id
    dnsZoneName: 'privatelink.vaultcore.azure.net'
    virtualNetworkName: vnet.name
    groupIds: [ 'vault' ]
  }
}

// NEW
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (useVirtualNetworkPrivateEndpoint) {
  name: virtualNetworkName

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

output endpoint string = keyVault.properties.vaultUri
output name string = keyVault.name
