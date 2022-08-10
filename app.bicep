targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The region for all resources to be deployed into.')
param location string = 'eastus2'

@description('The Azure Storage Blob SAS uri to be assigned to the VM application')
param saWorkerUri string

/*** EXISTING RESOURCES ***/

/*** RESOURCES ***/

resource ga 'Microsoft.Compute/galleries@2022-01-03' = {
  name: 'ga'
  location: location

  resource app 'applications' = {
    name: 'app'
    location: location
    properties: {
      description: 'Worker App'
      supportedOSType: 'Linux'
    }
  }
}

resource ver 'Microsoft.Compute/galleries/applications/versions@2022-01-03' = {
  name: '0.1.0'
  location: location
  parent: ga::app
  properties: {
    publishingProfile: {
      storageAccountType: 'Standard_LRS'
      enableHealthCheck: false
      excludeFromLatest: false
      manageActions: {
        install: 'mkdir -p /usr/share/worker-0.1.0 && tar -oxzf ./app --strip-components=1 -C /usr/share/worker-0.1.0 && cp /usr/share/worker-0.1.0/orchestrate.sh . && ./orchestrate.sh -i'
        remove: './orchestrate.sh -u'
      }
      replicaCount: 1
      source: {
        mediaLink: saWorkerUri
      }
    }
  }
}

/*** OUTPUTS ***/
