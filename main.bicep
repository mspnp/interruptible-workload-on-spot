targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The region for all resources to be deployed into.')
param location string = 'eastus2'

@description('The Spot VM ssh public key')
param sshPublicKey string

@description('The Spot Subnet Resource Id')
param snetId string

/*** EXISTING RESOURCES ***/

// Built-in Azure RBAC role that is applied to a Azure Storage queue to grant with peek, retrieve, and delete a message privileges. Granted to Azure Spot VM system mananged identity.
resource storageQueueDataMessageProcessorRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '8a0f0c08-91a1-4084-bc3d-661d67233fed'
  scope: subscription()
}

resource saWorkloadQueue 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: 'saworkloadqueue'

  resource qs 'queueServices' existing = {
    name: 'default'

    resource q 'queues' existing = {
      name: 'messaging'
    }
  }
}

/*** RESOURCES ***/

resource nic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: 'nic-spot'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: snetId
          }
          privateIPAllocationMethod: 'Dynamic'
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
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              keyData: sshPublicKey
              path: '/home/azureuser/.ssh/authorized_keys'
            }
          ]
        }
      }
      secrets: []
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

// Grant the Azure Spot VM managed identity with Storage Queue Data Message Processor Role permissions.
resource sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  scope: saWorkloadQueue::qs::q
  name: guid(resourceGroup().id, 'mi-vmspot', storageQueueDataMessageProcessorRole.id)
  properties: {
    roleDefinitionId: storageQueueDataMessageProcessorRole.id
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

/*** OUTPUTS ***/
