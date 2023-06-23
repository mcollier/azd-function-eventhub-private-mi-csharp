param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([ 'Basic', 'Standard', 'Premium' ])
param sku string = 'Standard'
param capacity int = 1

param isBehindVirtualNetwork bool = false
param virtualNetworkName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''

resource namespace 'Microsoft.EventHub/namespaces@2021-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
    capacity: capacity
  }

  resource networkRules 'networkRuleSets' = {
    name: 'default'
    properties: {
      defaultAction: isBehindVirtualNetwork ? 'Deny' : 'Allow'
      publicNetworkAccess: isBehindVirtualNetwork ? 'Disabled' : 'Enabled'
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (isBehindVirtualNetwork) {
  name: virtualNetworkName

  resource subnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = if (isBehindVirtualNetwork) {
  name: 'pe-${namespace.name}'
  location: location
  properties: {
    subnet: {
      id: vnet::subnet.id
      name: vnet::subnet.name
    }
    privateLinkServiceConnections: [
      {
        id: namespace.id
        name: 'plsc-${namespace.name}'
        properties: {
          privateLinkServiceId: namespace.id
          groupIds: [
            'namespace'
          ]
        }
      }
    ]
  }

  resource dnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'dnsZoneGroup-${namespace.name}'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: eventHubPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

resource eventHubPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (isBehindVirtualNetwork) {
  name: 'privatelink.servicebus.windows.net'
  location: 'Global'
}

module privateDnsZoneLink '../networking/dns-zone-vnet-mapping.bicep' = if (isBehindVirtualNetwork) {
  name: 'privatelink-${namespace.name}-vnet-link'
  params: {
    privateDnsZoneName: eventHubPrivateDnsZone.name
    vnetId: vnet.id
    vnetLinkName: 'vnet-${namespace.name}-link'
  }
}

output eventHubNamespaceName string = namespace.name
