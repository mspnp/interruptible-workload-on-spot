targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The region for all resources to be deployed into.')
param location string = 'eastus2'

/*** VARIABLES ***/

var subRgUniqueString = uniqueString('sa', subscription().subscriptionId, resourceGroup().id)

/*** EXISTING RESOURCES ***/

// Built-in Azure RBAC role that is applied to a Azure Storage queue to grant with peek, retrieve, and delete a message privileges. Granted to Azure Spot VM system mananged identity.
resource storageQueueDataMessageProcessorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8a0f0c08-91a1-4084-bc3d-661d67233fed'
  scope: subscription()
}

/*** RESOURCES ***/

resource nsgBastion 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-bastion'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowWebExperienceInBound'
        properties: {
          description: 'Allow our users in. Update this to be as restrictive as possible.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowControlPlaneInBound'
        properties: {
          description: 'Service Requirement. Allow control plane access.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'GatewayManager'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHealthProbesInBound'
        properties: {
          description: 'Service Requirement. Allow Health Probes.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionHostToHostInBound'
        properties: {
          description: 'Service Requirement. Allow Required Host to Host Communication.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSshToVnetOutBound'
        properties: {
          description: 'Allow SSH out to the VNet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '22'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowRdpToVnetOutBound'
        properties: {
          protocol: 'Tcp'
          description: 'Unused in this RI but required for ARM validation.'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '3389'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowControlPlaneOutBound'
        properties: {
          description: 'Required for control plane outbound. Regional prefix not yet supported'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionHostToHostOutBound'
        properties: {
          description: 'Service Requirement. Allow Required Host to Host Communication.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionCertificateValidationOutBound'
        properties: {
          description: 'Service Requirement. Allow Required Session and Certificate Validation.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '80'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'vnet-spot'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.200.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.200.0.0/26'
          networkSecurityGroup: {
            id: nsgBastion.id
          }
        }
      }
      {
        name: 'snet-spot'
        properties: {
          addressPrefix: '10.200.0.64/27'
        }
      }
    ]
  }

  resource snetBastion 'subnets' existing = {
    name: 'AzureBastionSubnet'
  }

  resource snetSpot 'subnets' existing = {
    name: 'snet-spot'
  }
}

resource pipBastion 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: 'pip-bastion'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
  sku: {
    name: 'Standard'
  }
}

resource bh 'Microsoft.Network/bastionHosts@2021-08-01' = {
  name: 'bh'
  location: location
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet::snetBastion.id
          }
          publicIPAddress: {
            id: pipBastion.id
          }
        }
      }
    ]
  }
  sku: {
    name: 'Standard'
  }
}

resource la 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'la${subRgUniqueString}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      legacy: 0
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: 'aiworkload'
  location: location
  kind: 'other'
  properties: {
    Application_Type: 'other'
    WorkspaceResourceId: la.id
  }
}

resource sa 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: 'sa${subRgUniqueString}'
  location: location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: true
  }

  resource bs 'blobServices' = {
    name: 'default'

    resource c 'containers' = {
      name: 'apps'
    }
  }

  resource qs 'queueServices' = {
    name: 'default'

    resource q 'queues' = {
      name: 'messaging'
    }
  }
}

resource miSpot 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'mi-spot'
  location: location
}

// Grant the User assigned identity with Storage Queue Data Message Processor Role permissions.
resource sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sa::qs::q
  name: guid(resourceGroup().id, miSpot.name, storageQueueDataMessageProcessorRole.id)
  properties: {
    roleDefinitionId: storageQueueDataMessageProcessorRole.id
    principalId: miSpot.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

/*** OUTPUTS ***/

output snetSpotId string = vnet::snetSpot.id
output aiConnectionString string = ai.properties.ConnectionString
output saName string = sa.name
output raName string = sqMiSpotVMStorageQueueDataMessageProcessorRole_roleAssignment.name
