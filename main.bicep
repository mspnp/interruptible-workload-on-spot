targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The region for all resources to be deployed into.')
param location string = 'eastus2'

@description('The Spot VM pass')
@secure()
param adminPassword string

/*** EXISTING RESOURCES ***/

// Built-in Azure RBAC role that is applied to a Azure Storage queue to grant with peek, retrieve, and delete a message privileges. Granted to Azure Spot VM system mananged identity.
resource storageQueueDataMessageProcessorRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '8a0f0c08-91a1-4084-bc3d-661d67233fed'
  scope: subscription()
}

/*** RESOURCES ***/

resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'vnet-spot'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.200.0.0/16'
      ]
    }
  }

  resource snet 'subnets' = {
    name: 'snet-spot'
    properties: {
      addressPrefix: '10.200.0.0/27'
    }
  }

}

resource pip 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: 'pip-spot'
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
  sku: {
    name: 'Basic'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: 'nic-spot'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: vnet::snet.id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
  dependsOn: []
}

resource vm 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: 'vm-spot'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v3'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: 'spot'
      adminUsername: 'azureuser'
      adminPassword: adminPassword
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: saVmDiagnostics.properties.primaryEndpoints.blob
      }
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: -1
    }
  }
}

resource saVmDiagnostics 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: 'savmspotdiagnostics'
  location: location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
}

resource saWorkloadQueue 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: 'saworkloadqueue'
  location: location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }

  resource qs 'queueServices' = {
    name: 'default'

    resource q 'queues' = {
      name: 'messaging'
    }
  }
}


// Grant the Azure Spot VM managed identity with Storage Queue Data Message Processor Role permissions.
resource sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope:saWorkloadQueue
  name: guid(resourceGroup().id, 'mi-vmspot', storageQueueDataMessageProcessorRole.id)
  properties: {
    roleDefinitionId: storageQueueDataMessageProcessorRole.id
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

/*** OUTPUTS ***/
