targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The region for all resources to be deployed into.')
param location string = 'eastus2'

@description('The Spot VM ssh public key')
param sshPublicKey string

@description('The Spot Subnet Resource Id')
param snetId string

@description('The Storage Account Name')
param saName string

/*** VARIABLES ***/

/*** EXISTING RESOURCES ***/

// Built-in Azure RBAC role that is applied to a Azure Storage queue to grant with peek, retrieve, and delete a message privileges. Granted to Azure Spot VM system mananged identity.
resource storageQueueDataMessageProcessorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8a0f0c08-91a1-4084-bc3d-661d67233fed'
  scope: subscription()
}

resource sa 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: saName

  resource qs 'queueServices' existing = {
    name: 'default'

    resource q 'queues' existing = {
      name: 'messaging'
    }
  }
}

resource ga 'Microsoft.Compute/galleries@2022-01-03' existing = {
  name: 'ga'

  resource app 'applications' existing = {
    name: 'app'

    resource ver 'versions' existing = {
      name: '0.1.0'
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

resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
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
        enabled: false
      }
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: -1
    }
    applicationProfile: {
      galleryApplications: [
        {
          packageReferenceId: ga::app::ver.id
          enableAutomaticUpgrade: false
          treatFailureAsDeploymentFailure: false
        }
      ]
    }
  }
}

// Grant the Azure Spot VM managed identity with Storage Queue Data Message Processor Role permissions.
resource sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sa::qs::q
  name: guid(resourceGroup().id, 'mi-vmspot', storageQueueDataMessageProcessorRole.id)
  properties: {
    roleDefinitionId: storageQueueDataMessageProcessorRole.id
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

/*** OUTPUTS ***/
