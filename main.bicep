targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The region for all resources to be deployed into. Defaults to the resource group\'s location for highest reliability.')
param location string = resourceGroup().location

@description('The Spot VM ssh public key')
param sshPublicKey string

@description('The Spot Subnet Resource Id')
param snetId string

@description('The Storage Queue Data Message Processor Role Assigment name')
param raName string

/*** EXISTING RESOURCES ***/

resource ga 'Microsoft.Compute/galleries@2022-01-03' existing = {
  name: 'ga'

  resource app 'applications' existing = {
    name: 'app'

    resource ver 'versions' existing = {
      name: '0.1.0'
    }
  }
}

resource miSpot 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: 'mi-spot'
}

// Grant the User assigned identity with Storage Queue Data Message Processor Role permissions.
resource sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' existing = {
  name: raName
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
}

resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: 'vm-spot'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${miSpot.id}': {}
    }
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
#disable-next-line adminusername-should-not-be-literal
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
  dependsOn: [
    sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment
  ]
}
