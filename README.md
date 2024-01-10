# Azure Function with Event Hub with Virtual Network features

This template will deploy an Azure Function, Event Hub, and supporting resources, with optional virtual network integration and private endpoints.  The following Azure resources are utilized:

- Virtual network with two subnets (optional)
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

The function app will be configured to use managed identity to connect to the Event Hub, Key Vault, and Azure Storage resources.  The Azure Storage connection string for `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` is placed within the provisioned Key Vault resource.

> NOTE: [Azure Files does not support use of managed identity when accessing the file share](https://learn.microsoft.com/azure/azure-functions/functions-reference?tabs=blob&pivots=programming-language-csharp#configure-an-identity-based-connection).  As such, the Azure Storage connection string for `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` is stored in Azure Key Vault.

The function app contains two functions - one to push events to the event hub, and another to receive events.  A function with a [timer trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-timer) is used to send an event to the event hub every 5-minutes.  The other function uses an [Event Hub trigger](https://learn.microsoft.com/azure/azure-functions/functions-bindings-event-hubs-trigger) to receive events from the event hub.

## High-level architecture

### No virtual network

The diagram below depicts the high-level resource architecture when no virtual network is used.  This may be suitable for local development when it is suitable to push the Function application code from a development workstation or CI/CD pipeline/workflow without a virtual network connected build agent.

![High-level architecture with no virtual network - Application Insights, Azure Storage account, Key Vault, Azure Function and Event Hub](assets/images/architecture-no-vnet.png)

### With virtual network (integration and private endpoints)

Alternatively, the Azure resources can be configured to use virtual network integration  and private endpoints by setting the `USE_VIRTUAL_NETWORK_INTEGRATION` and `USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT` environment settings to `true`.  Doing so will result in high-level architecture depicted below.

![High-level architecture with virtual network - Application Insights, Azure Storage account, Key Vault, Azure Function, Event Hub, virtual network, private endpoints, and private DNS zones](assets/images/architecture-with-vnet.png)

## Getting started

### Prerequisites

The following prerequisites are required to use this application.

- [Azure Developer CLI](https://aka.ms/azd-install)
- [.NET 6](https://dotnet.microsoft.com/en-us/download/dotnet/6.0)
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local)

Optionally, use the included dev container which contains the necessary prerequisites.

### Quickstart

1. Authenticate with AZD, initialize the project and set the necessary environment settings.

    ```bash
    # Log in to AZD.
    azd auth login

    # First-time project setup.
    azd init --template mcollier/azd-function-eventhub-private-mi-csharp
    ```

1. When prompted by AZD, provide the name for the AZD environment to use without a virtual network.
1. Create enviroment settings to indicate that virtual network integation and private endpoints are not used.  The template defaults to __not__ using virtual network integration nor private endpoints; using the environment settings makes this explicit.

    ```bash
    azd env set USE_VIRTUAL_NETWORK_INTEGRATION false
    azd env set USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT false
    ```

1. OPTIONAL - Create an AZD environmnent for use with a virtual network, and set the necessary environment settings.

    ```bash
    azd env new my-function-vnet
    azd env set USE_VIRTUAL_NETWORK_INTEGRATION true
    azd env set USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT true
    azd env set VIRTUAL_NETWORK_ADDRESS_SPACE_PREFIX 10.1.0.0/16
    azd env set VIRTUAL_NETWORK_INTEGRATION_SUBNET_ADDRESS_SPACE_PREFIX 10.1.1.0/24
    azd env set VIRTUAL_NETWORK_PRIVATE_ENDPOINT_SUBNET_ADDRESS_SPACE_PREFIX 10.1.2.0/24
    ```

1. For working without virtual network functionality, use the `azd up` command to provision the Azure resources and deploy the Azure Function code.  The Azure Function is a simple function which sends an event to the provisioned Event Hub every 5 minutes.

    ```bash
    # Provision the Azure resources and deploy the Azure Function app.
    azd up
    ```

1. (Optional) When using vnets and `USE_VIRTUAL_NETWORK_PRIVATE_ENDPOINT="true"`, use the `azd provision` command to provision the Azure resources.  You will not be able to deploy application code due to the private endpoint on the Azure Function.  Deployment will need to be done from an agent connected to the virtual network.

    > NOTE: If you want to deploy the function code and are not connected to the virtual network, use the Azure Portal to configure networking access restrictions for the function app to allow public access.  The run `azd deploy` to deploy the application.
