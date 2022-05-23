targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The VNet Resource ID that the VM Spot will be joined to')
@minLength(79)
param targetVnetResourceId string

@description('The Azure Spot  VM region. This needs to be the same region as the vnet provided in these parameters.')
@allowed([
  'australiaeast'
  'canadacentral'
  'centralus'
  'eastus'
  'eastus2'
  'westus2'
  'francecentral'
  'germanywestcentral'
  'northeurope'
  'southafricanorth'
  'southcentralus'
  'uksouth'
  'westeurope'
  'japaneast'
  'southeastasia'
])
param location string = 'eastus2'

@description('The Spot VM pass')
@secure()
param adminPassword string

/*** EXISTING HUB RESOURCES ***/

resource targetVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-08-01' existing = {
  name: targetVnetResourceId
}

resource snet 'Microsoft.Network/virtualNetworks/subnets@2021-08-01' existing = {
  parent: targetVirtualNetwork
  name: 'snet-spot'
}

/*** RESOURCES ***/

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
            id: snet.id
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

resource virtualMachineName 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: 'vm-spot'
  location: location
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
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
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
        storageUri: 'https://diagstoragespot2019.blob.core.windows.net/'
      }
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: -1
    }
  }
  dependsOn: [
    diagnosticsStorageAccountName
  ]
}

resource diagnosticsStorageAccountName 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: 'diagstoragespot2019'
  location: location
  properties: {}
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
}

/*** OUTPUTS ***/
