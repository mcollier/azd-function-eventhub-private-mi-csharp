param name string
param location string = resourceGroup().location
param tags object = {}

param virtualNetworkAddressSpacePrefix string
param subnets array

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressSpacePrefix
      ]
    }
    subnets: subnets
  }
}

output virtualNetworkName string = vnet.name
