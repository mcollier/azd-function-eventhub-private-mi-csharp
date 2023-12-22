# WARNING - Work in Progress!
## Azure Developer CLI - Azure Function with Event Hub with Virtual Network capabilities

This AZD template will deploy the following resources:
- Virtual network with two subnets
- Azure Function Premium plan
  - Optional support for virtual network integration
- Azure Function app
  - Optional support for virtual network private endpoint
- Application Insights
- Log Analytics workspace
- Key Vault
  - Optional support for virtual network private endpoint
  - Azure Storage connection string is set as a Key Vault secret
- Event Hub namespace and event hub
  - Optional support for virtual network private endpoint
- Storage account
  - Optional support for virtual network private endpoint
- User assigned managed identity
  - RBAC for Event Hub, Key Vault, and Azure Storage resources in the resource group

The function app will be configured to use the managed identity to connect to the Event Hub and Azure Storage resources.  The Azure Storage connection string for `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` is placed within the provisioned Key Vault resource.

### Getting started

1. Create two AZD environments - one for local dev (no vnets) and one for working with vnets.
1. Add the following settings to your AZD environment for working with vnets.  Change the virtual network address space as desired.
    - `USE_VIRTUAL_NETWORK_INTEGRATION="true"`
    - `USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT="true"`
    - `VIRTUAL_NETWORK_ADDRESS_SPACE_PREFIX="10.1.0.0/16"`
    - `VIRTUAL_NETWORK_INTEGRATION_SUBNET_ADDRESS_SPACE_PREFIX="10.1.1.0/24"`
    - `VIRTUAL_NETWORK_PRIVATE_ENDPOINT_SUBNET_ADDRESS_SPACE_PREFIX="10.1.2.0/24"`
1. Add the following settings to your AZD environment for local development (no vnets):
    - `USE_VIRTUAL_NETWORK_INTEGRATION="false"`
    - `USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT="false"`
1. For working locally (no vnets), use the `azd up` command to provision the Azure resources and deploy the Azure Function code.  The Azure Function is a simple function which sends an event to the provisioned Event Hub every 5 minutes.
1. When using vnets and `USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT="true"`, use the `azd provision` command to provision the Azure resources.  
   You will not be able to deploy application code due to the private endpoint on the Azure Function.  Deployment will need to be done from an agent connected to the virtual network. 
  
