# WARNING - Work in Progress!
## Azure Developer CLI - Azure Function with Event Hub with Virtual Network capabilities

This AZD template will deploy the following resources:
- Virtual network with two subnets
- Azure Function Premium plan
  - virtual network integrated
  - support for private endpoint
- Application Insights
- Log Analytics workspace
- Key Vault
  - not yet set up with a private endpoint
- Event Hub namespace and event hub (with private endpoint)
- Storage account (with private endpoint)
- User assigned managed identity
  - RBAC for Event Hub, Key Vault, and Azure Storage resources in the resource group

The function app will be configured to use the managed identity to connect to the Event Hub and Azure Storage resources.  The Azure Storage connection string for `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` is placed within the provisioned Key Vault resource.

### Getting started

1. `azd up` to provision the Azure resources and deploy the Azure Function code.
