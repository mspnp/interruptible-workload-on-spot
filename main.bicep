targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The Azure Spot VM region. This needs to be the same region as the vnet provided in these parameters.')
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
        storageUri: 'https://${sa.name}.blob.core.windows.net/'
      }
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: -1
    }
  }
  dependsOn: [
   sa
  ]
}

resource sa 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: 'savmspotdiagnostics'
  location: location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
}

/*** OUTPUTS ***/
