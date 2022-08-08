# Interruptible workloads on Azure Spot VM/VMSS instances

## Introduction

This reference implementation provides you with a workload that is meant to guide you to explore the Azure Spot VM manage service from a development and architectural perspective to get the fundamentals, and most of the moving parts so you feel comfortable while building your own workload as a next step. As an application architect, you will know how to design a solution to support interruptions. As a developer, you want to use this workload example to reference when writing code.

Azure as major cloud must provision spare capacity along all its offered regions so it can respond on demand when new resources are created. Meanwhile that capacity remains idle, you are given with the chance to [oportuniscally deploy that compute in your subscription at discount prices and capped at **Pay as you go** prices using Azure Spot VM/VMSS](https://azure.microsoft.com/pricing/spot-advisor/).

As a general thought, keeping the OpEx under control is a predominant practice when running solutions on the cloud, and [the cost optimizations pillar from the Well Architected Framework](https://docs.microsoft.com/azure/architecture/framework/cost/overview) can further assist you finding the right strategy for your architecture. While the number one motivation to choose using Azure Spot VM/VMSS instances is significant cost savings at the infrastructure level, you have to keep in mind that you need to build reliable interruptible workloads that can run on top of this Azure managed service.

In the era of Distributed Systems, a technique that gained popularity is the Chaos Engineering that consist of introducing detrimental conditions without previous notice to experiment with workloads running peacefully in production. This helps to test their fault tolerance and resilence with the main objective of detecting the workloads that can withstand operating normally and those that need to be improved to work properly under unfavorable circumstances. As described above Azure Spot VM/VMSS is not designed to cause breakdowns, and yet you will find that the same system properties are suitable when building applications that can run efficiently on top of this Azure service.

Therefore, workloads will have the requirement to be designed fault tolerant and resilient, so they should be capable of being unexpectedly and reliable interrupted. Typically, such workloads are able to deal with high levels of uncertainty at the time of being deployed, and can recover after being forcedly shutdown or even better they can gracefully shutdown under 30 sec notification prior to eviction.

Some good candidates to run on top of Azure Spot VM are batch processing apps, workloads that are not time critical for background processing jobs, as well as those large enough as in data analytics but that you don’t care if they really finish in a certain period of time, tasks consired as optional or with lower priority such us spawning a CI/CD agent for a dev/test environment, short lived jobs that can lose its progress without affecting the end result as many times as evicted until completion. Some orgnizations might categorize long running process when they are time constrained to units like "weeks" or even "months", as an application architect you might want to team up with your business orgnization to discover your own long runnings. Azure Virtual Machine Scalsets (VMSS) is also offered with priority **Spot**, and it is an underlaying service that will represent nodes for a Azure Kubernetes Service (AKS) cluster. As a result, stateless applications as well as opportunistic scale out scearios are also possible candidates to be build with Azure Spot VMSS in mind if they are meant to run from an AKS cluster. This later use case is out of scope in this reference implementation. As general guidance, you should consider avoid using Azure Spot VM/VMSS if your application is under a strict SLA that could be compromised by compute eventual interruptions, if your are planning to provision sticky session solutions or provided your workload is not designed to be interrupted, or it is stateful by nature. In `production` it is recommended to keep a guaranteed amount of Azure VM instances with **Regular Priority** to be safely compliance with your application SLA in addition to some amount configured with **Spot priority** for cost optimization purposes. If workload is so interruptable that it doesn't need an SLA, you might consider going over full **Spot Priority** even in `production`.

In a nutshell, Azure Spot VM/VMSS are compute Infrastructure as a Service available in Azure that serves without a SLA once created, which means that it can be terminated at any moment with up to 30 secs notification. In other words, at any point in time when Azure needs the capacity back, the Azure infrastructure will evict the service by deallocating or deleting the resources based on your configured Eviction policy.

You are acquiring unused (if any) ephemeral compute capacity that offers no high availability guarantees. Given that, Azure Spot VM/VMSS is a limited resource that won’t be always at your disposal.

From the aforementioned concepts, you could model this Azure service as a machine that will change its state depending on users input or events triggered by the Azure infrastructure. If this idea gets a bit more generalized, you will recognize this as a kind of finite-state machine. You may find valuable this infrastructure thinking to properly design workloads capable of adjusting to different conditions they might run into Azure Spot VM/VMSS.

The Azure Spot VM/VMSS instances while be transitioning one of the following valid states at the time, and your workload has to be able to behave accordingly on top of:
1. Stopped or Deleted (eviction policy based)
1. Running (based on capacity and max price you set)

![State diagram depicting how Azure VM Spot VM/VMSS behaves depending on policy, capcity ad price.](./spot-statediagram.png)

| Current State  | Input   | Conditions                                                                     | Next State | Output                                                                                                               |
|----------------|---------|------------------------------------------------------------------------------- |------------|----------------------------------------------------------------------------------------------------------------------|
| *              | Deploy  | Max Price >= Current Price and Capacity = Available                            | Running    | You pay the Max Price you set and underlaying disks                                                                  |
| Running        | Evict   | Max Price =  -1            and Capacity = Available                            | Running    | You pay the VM Price and underlaying disks                                                                           |
| Running        | Evict   |                                Capacity = Unavailable and Policy = Deallocate  | Stoped     | Compute capacity gets deallocated while you pay for underlaying disk. It is possible to restart the machine          |
| Running        | Evict   |                                Capacity = Unavailable and Policy = Delete      | Deleted    | You are not charged at this point since disks are deleted                                                            |
| Running        | Evict   | Max Price <  Current Price                            and Policy = Deallocate  | Stoped     | You pay for underlaying disk and can restart the machine                                                             |
| Running        | Evict   | Max Price <  Current Price                            and Policy = Delete      | Delete     | You are not charged at this point since disks are deleted                                                            |
| Stoped         | Restart | Max Price <  Current Price                            and Policy = Deallocate  | Stoped     | You pay for underlaying disk and can restart the machine                                                             |
| Stoped         | Restart | Max Price <  Current Price                            and Policy = Delete      | Delete     | You are not charged at this point since disks are deleted                                                            |
| Stoped         | Restart | Max Price >= Current Price and Capacity = Available                            | Running    | You pay the Max Price you set and underlaying disks                                                                  |

> **Note**
> It is paramount to understand that under a constraint capacity event from a particular location, and/or provided the current market prices surpass the Max Price you set, the Azure infrastructure will collect its compute capacity for Azure Spot VM following your configured Eviction policy as mentioned above. If you configured your Azure Spot VM for deallocation under an eviction event, it is responsibility of the application operator (automated or manually) to restart the Azure Spot VM once the capacity becomes available.

## Concepts

Some important concepts when building on top of Azure Spot VM instances are:

1. Subscription Limits: 20 cores per subscription by default. Some Subscriptions are not supported (please take a look at the list of supported supported types).
1. Eviction:
   1. Rate: it is nothing but the chances of being evicted at a specific location. A common practice is to choose the location based on the eviction rate by SKU querying the pricing history view from Azure Portal in addition to [Azure Spot advisor].
   1.	Type: you can choose between **Max Price or Capacity** or **Capacity Only**
   		1. Capacity: when using Azure Spot Virtual Machine Scalesets (VMSS) with **Manual** scaling, a good practice is to enable the **Try to Restore** option if your policy eviction is **Deallocate**. Provided Azure infrastructure collected capacity back, this configuration looks for those clusters that has the most spare capacity, and will attempt to reploy your deallocated instances on top of them. Therefore, it provides your Azure Spot VMSS with better surviving chances next time an eviction event kicks in. When configured with **Autoscale**, this option is not avaialble as this implements its own logic to reallocate instances.
   			 1. VM Configuration: as flexible as choosing the SKU, the better are chances to be allocate Azure Spot VM/VMSS. Some SKU(s) like B-series or Promo versions of any size are not supported.
   			 1. Location: same as in SKU, if your workload can run from any region, it improves the chances to be deployed as well as with less chances of being deallocated if you choose carefully considering the eviction rates. Please take into account that Microsoft Azure China 21Vianet is not supported.
   			 1. Time of the Day, Weekends, Seasons (i.e. Christmas), and other time based considerations are important factors when making a final decision between Azure Spot over regular VMs/VMSS.
   		1. Current VM Price vs Max Price (you set): if you are willing to pay up to the **Pay as you go** rate, it is possible to prevent from being evicted based on price reasons by setting the your **Max Price** to `-1` wich is known as **Eviction Type Capacity Only**. If pricing is a constraint for your business organization goals, **Eviction Type Max Price or Capacity Only** is recommended for you, and in this case you can adjust the right **Max Price** at any moment by taking into account that changing this value requires to deallocate the VM/VMSS first to take effect. If you choose the later, it is good idea to analyze the price history and **Eviction Rate** for the regions you are targeting to.
   1. Policy:
   		1. Delete
   		 	1. You free up the Cores from your Subscription, so shared subscriptions or multiple workloads using Azure Spot VM instances can be befitted from this.
   		 	1. You are not longer charged for the disk as they get deleted along with the Azure Spot VM
   		1. Deallocate
   		 	1. Change VM state to the stopped-deallocated state
   		 	1. Allowing you to redeploy it later.
   		 	1. You are still being charge for the underlaying disks
   		 	1. It consumes Cores quota from your Subscription
   1. Simulation: it is possible to [similate an eviction event](https://docs.microsoft.com/azure/virtual-machines/spot-portal#simulate-an-eviction) when Azure needs the capacity back. You want to get familiarized with this since it is going to be recommend for you to simulate interruptions from dev/test environments to guarantee your workload is fully interrumptible before deploying to production.
1. Events: [Azure Scheduled Events] is a metadata service in Azure that helps to discover forthcoming maintenance events associated to the Virtual Machine resource type. The general recommendation when using Virtual Machines is to routinely query this endpoint, so you are given the opportunity to prepare for disruption. One of the platform event types being scheduled that you will want to notice is `Preempt` as this signals the imminent eviction for a particular resource. This event type is scheduled with 30 seconds notice in advance. Althought the recommendation is to [poll the service once per second](https://docs.microsoft.com/azure/virtual-machines/linux/scheduled-events#polling-frequency) to have as much time as possible to gracefully interrupt the processing, you could fine tune the polling frenquency as you see fit. In the end, the periodicity will be mandated by your workload needs and resource utilization.
1. Metadata Apis: [Azure Retail Prices API]

## The Workload

One of well-suited workload types for Azure Spot VM are batch processing apps. This reference implementation contains a simple and asyncronously queue-processing worker (C#, .NET 6) implemented in combination with [Azure Queue Storage](https://docs.microsoft.com/azure/storage/queues/storage-queues-introduction) and demostrate how to query the [Azure Scheduled Events] REST endpoint that allows the workload to be signaled prior to eviction so it can anticipate such disruption event and prepare for interruption limiting its impact.

### Planning for being Fault Tolerant

#### The application states

When building reliable interruptible workloads, you will be focused on four main stages during their lifecycle that will derive into changes of states within your application:

1. Start: after the application `warmup` state is completed, you could consider internally transitioning into `processing` state. An important aspect to contemplate is a previous forced shutdown having as side effect some incomplete processing, so the recommendation is to implement idempotency when applicable. Additionally, it is a good practice to save the context by creating checkpoints regularly. This enables a more efficient recovery strategy which is recover from the latest well-known checkpoint instead of starting all over the processing again.
1. Shutdown: your workload is in `processing` state, and at the same time an eviction event is triggered by the Azure infrastructure. Compute capacity must be collected from Azure Spot instances, and as a result an eviction notice will take place in your application. It is time for your application to change the state to `evicted`, and implement the logic to respond by gracefully shutting down within 30 secs by releasing resources such us draining connections, event logging, or prepare to be forcedly deallocated or deleted based on your **Evition Policy**. In the later configuration, as a general practice you can not persist any progress or data on the file system since disks are being removed along with the Azure VM.
1. Recover: as part of this stage, your workload is `redeployed` or `recreated` depending on your **Eviction Policy** preference. These possible states during a recovery are dectected. You implement the logic to deal with a prior forced shutdown so it is capable of recovering from a previous backup/checkpoint if neeeded.
1. Resume: the application is about to continue processing after a best effort to recover the context prior to eviction. It is good idea to transition into `warmup` state to ensure the workload is healthy and ready to start.

![A workload lifecycle diagram depicting the four possible stages interruptible workloads should contemplate during their lifetime](./lifecycle-spot-vm.svg)

> **Note**
> The aforementioned states are just a reduced list of possible valid conditions for an reliable interruptible workload. You might find others that are convenient for your own workloads.

#### The system states

if you closely look at this reference implementation you will notice it is a Distributed Producer Consumer system type where the interruptible workload is nothing but a batch processing app acting as the consumer. Since you are mainly considering Azure Spot VM to save costs, the recommendation is to look into the issues that may arise in a solution of this kind, such as concurrency problems as shown below, and get them mitigated to avoid wasting compute cycles:

1. Deadlock
1. Starvation

As a general recommendation, you must always take into account edge cases and common pitfalls associated to the system types you are building, and design their architectures to be good citizens while running on top of Azure Spot VMs.

> **Note**
> This reference implementation follows the simple concurrency stragey: **Do-Nothing**. Please note that you are going to deploy a single interruptible workload instance (consumer), and produce a moderate and discrete amount of messages. Therefore, expect no `Deadlock` neither `Starvation` as eventual system valid states while running it. While a specific recommendation could be to prevent your system from running into such states, you could consider handling them if detected at the **Orchestration** time as another mitigation strategy. But this is out of scope from this reference implementation.

#### The Orchestration

As this is aforementioned from the previous section, the orchestration can be scoped to coordinate at the application level or go beyond, and implement broader capabilities like system recovery as you see fit. Whereas, this reference implementation is focused on scheduling the interruptible workload into the Azure Spot VM operating system. In other words, it is enabling .NET worker application as a service as well as starting it for the first time.

This archestration appraach in which the interruptible workload is installed as a service is going to be really helpful to let the operating system get this automatically started when Spot VM starts up. This way, the application will be able to continue processing messages without human intervention after eviction. Once the application is running it will transition the `Recover` -> `Resume` -> `Start` [application states](#the-application-states).

By design, this is a [bash script](./orchestrate.sh) that is executed by using VM Aapplications. This Azure resource allows to publish and distrubute specific application versions for a particular VM. Once it is set, it downloads an Azure Blob Storage file containing the interruptible workload package. The package is uncompressed using the installation command, and execute the `orchestrate.sh` within it.

![Depict the Azure Spot VM infrastructure at orchestration time](./spot-orchestrationdiagram.png)

>**Note**
>Althought this Reference Implmentation will walkthrought the process of packaging, publishing and distributing a single app, this is prescribed as one time activity following a set of step by step instructions. Whereas in productive systems, you will want to deploy many times to production within a day, week or month depending on how often the team agrees upon that, manage multiple revision/versions and applications. That being said, it is recommended for you to implement CI/CD pipelines to automate this or implement any other practice your orgazation typically follows to install applications.

Another important orquestration related aspect is to understand how to scale your workload within a single VM instance, so it is more resource efficient.

**Scale up strategy**

In this case your workload is built with no artificial constraints, and will grow to consume available resources in your VM instance without exhausting them. From the orchestration point of view, you want to ensure that it is running a SINGLETON of the workload and let this organically request resources as designed.

![Depict the Azure Spot VM infrastructure orchestration scale up strategy](./spot-orchestrationscaleupdiagram.png)

**Scale out strategy**

Alternatively, if the workload resources specs are limited by design, or in other words this can not grow to consume VM resources, ensure you right size the VM to orchestrate one or more whole instances (multiple) of your workload, so there is no wasted over provisioning of compute in your Spot VM.

![Depict the Azure Spot VM infrastructure orchestration scale out strategy](./spot-orchestrationscaleoutdiagram.png)

### Installation

#### Prerequisites

1. An Azure subscription. You can [open an account for free](https://azure.microsoft.com/free).
1. [Azure CLI installed](https://docs.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest) or you can perform this from Azure Cloud Shell by clicking below.

   ```bash
   az login
   ```

1. Ensure you have latest version

   ```bash
   az upgrade
   ```

   [![Launch Azure Cloud Shell](https://docs.microsoft.com/azure/includes/media/cloud-shell-try-it/launchcloudshell.png)](https://shell.azure.com)


1. Generate new Spot VM authentication ssh keys by following the instructions from [Create and manage SSH keys for authentication to a Linux VM in Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/create-ssh-keys-detailed). Alternatively, quickly execute the following command:

   ```bash
   ssh-keygen -m PEM -t rsa -b 4096 -C "azureuser@vm-spot" -f ~/.ssh/opsvmspots.pem
   ```

1. Ensure you have **read-only** access to the private key.

   ```bash
   chmod 400 ~/.ssh/opsvmspotkeys.pem
   ```

1. (Optional | Local Development) [Docker](https://docs.docker.com/)

1. (Optional | Local Development) [OpenSSL](https://www.openssl.org/)

1. [.NET 6.0 SDK](https://dotnet.microsoft.com/download/dotnet/6.0)

1. (Optional) [JQ](https://stedolan.github.io/jq/download/)

> **Note**
> :bulb: The steps shown here and elsewhere in the reference implementation use Bash shell commands. On Windows, you can [install Windows Subsystem for Linux](https://docs.microsoft.com/windows/wsl/install#install) to run Bash by entering the following command in PowerShell or Windows Command Prompt and then restarting your machine: `wsl --install`

#### Expected Results

Following the steps below will result in the creation of the following Azure resources that will be used throughout this Reference Implementation.

| Object                                    | Purpose                                                                                                                                                                                                                                                                          |
|-------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| A Resource Group                          | Contains all of your organization's related networking, and copmute resources.                                                                                                                                                                                                   |
| A single Azure Spot VM instance           | Based on how flexible you can be you selected an Azure VM size, and it gets deployed so your interruptible workloads can be installed and executed from there. In this Reference Implementation, the `Standard_D2s_v3` size was chosen and the VM is assigned a System Managed Identity to give it Azure RBAC permissions as a Storage Queue Consumer. |
| A Virtual Network                         | The private Virtual Network that provides with connectivity over internet to the Azure VM so it can be accessed. For more information, please take a look at [Virtual networks and virtual machines in Azure](https://docs.microsoft.com/azure/virtual-network/network-overview). For VNET enabled VMs like this, the [Azure Scheduled Events] Metadata Service is available from a static nonroutable IP. |
| A Network Card Interface                  | The must have NIC that will allow the interconnection between a virtual machine and a virtual network subnet.                                                                                                                                                                    |
| A Spot VM Subnet                          | The subnet that the VM is assigned thought its NIC. The subnet allows the NIC to be assigned with a private IP address within the configured network adrress prefix.                                                                                                             |
| A Bastion Subnet                          | The subnet that the Azure Bastion is assigned to. The subnet supports applying NSG rules to support expected traffic flows, like opening port **22** against the Spot VM private IP. |
| An Azure Bastion                          | The Azure Bastion that allows you to securely communicate with over Internet from your local computer to the Azure Spot VM. |
| A Public IP address                       | The public IP address of the Azure Bastion host. |
| A Storage Account (diagnostics)           | The Azure Storage Account that stores the Azure Spot VM boot diagnostics telemetry.  |
| A Storage Account (queue)                 | The Azure Storage Account that is a component of the interruptible workload, that represents work to be completed. |

![Depict the Azure Spot VM infrastructure after deployment](./spot-deploymentdiagram.png)

> **Note**
> :bulb: Please note that the expected resources for the Spot instance you about to create are equal to what you would create for a regular Azure Virtual Machine. Nothing is changed but the selected **Priority** which is set to **Spot** in this case, while creating an on-demand it would have been set to **Regular**.

#### Planning

At this point, you have learnt that as an Architect you are tasked at being flexile which could be translated into look for as many options as you can find that align well with your organization business goals in terms of budget while at the same time this selection meet the non-functional requirements at the capacity level for your workload.

1. Get acquiented with the VM sizes Azure can offer you, and try to pick out some of them. The following command list VM Skus in `US East 2` that has a number of cores not greather than `8` by excluding from the results not supported options when using Azure Spot VM/VMSS instances:

   > **Note**
   > :bulb: In the future when creating your own interruptible workload ensure you right size your compute requirements, and include the filters in the following query or consider using the [Virtual machine selector tool](https://azure.microsoft.com/pricing/vm-selector/).

   ```bash
   az vm list-sizes -l eastus2 --query "sort_by([?numberOfCores <=\`8\` && contains(name,'Standard_B') == \`false\` && contains(name,'_Promo') == \`false\`].{Name:name, Cores:numberOfCores, RamMB:memoryInMb, DiskSizeMB:resourceDiskSizeInMb}, &Cores)" --output table
   ```

   The command above display an output similar to the following:

   ```output
   Name                  Cores    RamMB    DiskSizeMB
   --------------------  -------  -------  ------------
   Standard_D1_v2        1        3584     51200
   Standard_F1           1        2048     16384
   ...
   Standard_D2_v2        2        7168     102400
   Standard_D11_v2       2        14336    102400
   ...
   Standard_D12_v2       4        28672    204800
   Standard_F4           4        8192     65536
   ...
   Standard_NC6s_v3      6        114688   344064
   Standard_NV6          6        57344    389120
   ...
   Standard_E8as_v4      8        65536    131072
   Standard_D4           8        28672    409600
   ...
   ```

1. Before laying out an infrastructure proposal, you have to be aware about pricing. You can navigate to the [Azure Spot advisor] to contrast alternatives you have found from the previous step to apply another fitler more budget related for a final cherry-pick. Alternatively, if you had installed JQ you could execute the following command:

   ```bash
   curl -X GET 'https://prices.azure.com/api/retail/prices?api-version=2021-10-01-preview&$filter=serviceName%20eq%20%27Virtual%20Machines%27%20and%20priceType%20eq%20%27Consumption%27%20and%20armRegionName%20eq%20%27eastus2%27%20and%20contains(productName,%20%27Linux%27)%20and%20contains(skuName,%20%27Low%20Priority%27)%20eq%20false' --header 'Content-Type: application/json' --header 'Accept: application/json' | jq -r '.Items | sort_by(.skuName) | group_by(.armSkuName) | [["Sku Retail[$/Hour] Spot[$/Hour] Savings[%]"]] + [["-------------------- ------------ ------------ ------------"]] + map([.[0].armSkuName, .[0].retailPrice, .[1].retailPrice, (100-(100*(.[1].retailPrice / .[0].retailPrice)))]) | .[] | @tsv' | column -t
   ```

   > **Note**
   > :bulb: You could modify this query by changing the filter for example to incorporte the VM sizes you are mostly interested in as well as specific regions.

   You should get an output similar as shown below:

   ```output
   Sku                        Retail[$/Hour]  Spot[$/Hour]  Savings[%]
   --------------------       ------------    ------------  ------------
   Standard_DC16ds_v3         1.808           0.7232        60
   Standard_DC16s_v3          1.536           0.6144        60
   Standard_DC1ds_v3          0.113           0.0452        60
   ...
   Standard_NC48ads_A100_v4   7.346           2.9384        60
   Standard_NC96ads_A100_v4   14.692          5.8768        60
   Standard_ND96amsr_A100_v4  32.77           16.385        50
   ```

   > **Note**
   > :bulb: Provided you have choosen a **Max Price and Capacity** eviction policy, it is a good practice to regularly use the [Azure Retail Prices API] to check whether the **Max Price** you set is doing well against  **Current Price**. You might want to consider scheduling this query and respond with **Max Price** changes as well as gracefully deallocate the Virtual Machine accordingly.

#### Clone the repository

1. Clone this repository

   ```bash
   git clone https://github.com/mspnp/interruptible-workload-on-spot.git
   ```
1. Navigate to the interruptible-workload-on-spot folder

   ```bash
   cd ./interruptible-workload-on-spot/
   ```

#### (Optional | Local Development) Execute the Interruptible Workload locally

You might want to get a first hand experience with the interruptible workload by running this locally. This will help you to get familiarized with the app, or you could skip this step and [deploy this into Azure](./README.md#deploy-the-azure-spot-vm).

1. Generate a new self signed certificate to be able to listen over https when using [Azurite emulator for local Azure Storage development](https://docs.microsoft.com/azure/storage/common/storage-use-azurite?tabs=docker-hub):

   ```bash
   mkdir certs \
   && openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ../certs/127.0.0.1-azurite.key -out ../certs/127.0.0.1-azurite.crt -addext "subjectAltName=IP:127.0.0.1" -subj "/C=CO/ST=ST/L=LO/O=OR/OU=OU/CN=CN" --passout pass: \
   && openssl pkcs12 -export -out ../certs/127.0.0.1-azurite.pfx -inkey ../certs/127.0.0.1-azurite.key -in ../certs/127.0.0.1-azurite.crt --passout pass:  \
   && sudo cp ../certs/127.0.0.1-azurite.crt /usr/local/share/ca-certificates \
   && sudo update-ca-certificates \
   && openssl verify /usr/local/share/ca-certificates/127.0.0.1-azurite.crt \
   && cp /etc/ssl/certs/127.0.0.1-azurite.pem ../certs
   ```

   > **Note**
   > The instructions provided above must be used only for development purposes.

   > **Note**
   > Listening over https is required by Azurite emulator to enable OAuth support as well as trusting the self signed cert to be able to make secure calls using the SDK in development

   > **Warning**
   > The instructions provided above are valid for Ubuntu machines or WLS, while you could opt to use `dotnet dev-certs` if you are in Windows or MacOS. For more information, please let's take a look at https://github.com/Azure/Azurite#pfx

1. Run Azurite emulator for local Azure Storage Qeuee developmet

   ```bash
   docker run -d -v $(pwd)/certs:/workspace -p 10001:10001 --net="host" mcr.microsoft.com/azure-storage/azurite azurite-queue --queueHost 0.0.0.0 --oauth basic --cert /workspace/127.0.0.1-azurite.pem --key /workspace/127.0.0.1-azurite.key --debug /workspace/debug.log --loose --skipApiVersionCheck --disableProductStyleUrl
   ```

1. Setup the Azure Storage Queue using the REST Apis

   Set the http headers

   ```bash
   x_ms_date="x-ms-date:$(TZ=GMT date "+%a, %d %h %Y %H:%M:%S %Z")"
   x_ms_version="x-ms-version:2021-08-06"
   ```

   Create a shared key signature for the create queue endpoint

   ```bash
   signature_create_queue=$(printf "PUT\n\n\n\n\n\n\n\n\n\n\n\n${x_ms_date}\n${x_ms_version}\n/devstoreaccount1/devstoreaccount1/messaging" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$(printf 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==' | base64 -d -w0 | xxd -p -c256)" -binary |  base64 -w0)
   ```

   Make a http call to create the Azure Storage Queue named **messaging**

   ```bash
   curl -X PUT -k -v -H "${x_ms_date}" -H "${x_ms_version}" -H "Authorization: SharedKey devstoreaccount1:$signature_create_queue" https://127.0.0.1:10001/devstoreaccount1/messaging
   ```

   Create a shared key signature for the create queue message endpoint

   ```bash
   signature_create_queue_messages=$(printf "POST\n\n\n67\n\napplication/x-www-form-urlencoded\n\n\n\n\n\n\n${x_ms_date}\n${x_ms_version}\n/devstoreaccount1/devstoreaccount1/messaging/messages" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$(printf 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==' | base64 -d -w0 | xxd -p -c256)" -binary |  base64 -w0)
   ```

   Generate **100** messages

   ```bash
   for i in {1..100}; do curl -X POST -k -v -H "${x_ms_date}" -H "${x_ms_version}" -H "Authorization: SharedKey devstoreaccount1:$signature_create_queue_messages" https://127.0.0.1:10001/devstoreaccount1/messaging/messages -d '<QueueMessage><MessageText>Hello World</MessageText></QueueMessage>';done;
   ```

1. Run the worker application

   ```bash
   dotnet run --project src/
   ```

   > **Note**
   > When runnning in **Develoment** mode after querying 10 times the Azure Event Schedule detects an eviction notice emulating an Azure infrastructure event claiming your Spot VM instance. The app proceed to shutdown the workload.


#### Deploy the Azure Spot VM

1. Create the Azure Spot VM resource group

   ```bash
   az group create -n rg-vmspot -l centralus
   ```

1. Create the Azure Spot VM deloyment

   ```bash
   az deployment group create -g rg-vmspot -f main.bicep -p location=westcentralus
   ```

1. Generate **100** messages

   ```bash
   for i in {1..100}; do az storage message put -q messaging --content $i  --account-name saworkloadqueue;done;
   ```

#### Package the workload

1. Build the sample workder

   ```bash
   dotnet build ./src -c Release --self-contained --os linux -o worker
   ```

1. Copy the systemd configuration file

   ```bash
   cp interruptible-workload.service worker/.
   ```

1. Copy the orchestration file

   ```bash
   cp orchestrate.sh worker/.
   ```

   > *Note*
   > Once the interruptible workload package gets downloaded into the Spot VM usgin VM Applications, this file will be executed to kick off the orchestration. The orquestration consist on ensuring a single interruptible workload instance by installing this as a service into the VM, and right after start the service for the first time.

1. Embed the Azure Application Insights Connection String

   ```bash
   AI_CONNSTRING=$(az deployment group show -g rg-vmspot -n main --query properties.outputs.aiConnectionString.value -o tsv)

   sed -i "s#\(ConnectionString\" : \"\)#\1${AI_CONNSTRING//&/\\&}#g" ./worker/appsettings.json
   ```

   > **Note**
   > The general recommendation is not to embed secrets in your application but to use a secret storage management solution such us Azure KeyVault. In this reference implementation, we embed this connection string for the sake of simplicity.

1. Package the worker sample

   ```bash
   pushd ./worker
   tar -czf ../worker-0.1.0.tar.gz *
   popd
   rm -rf worker/
   ```

#### Upload the packaged workload, and the orchestration script

1. Upload the package to the container apps

   ```bash
   az storage blob upload --account-name savmapps --container-name apps --name worker-0.1.0.tar.gz --file worker-0.1.0.tar.gz
   ```

1. Generate a valid SAS uri expiring in seven days packaged workload

   ```bash
   saWorkerUri=$(az storage blob generate-sas --full-uri --account-name savmapps --container-name apps --name worker-0.1.0.tar.gz --account-key $(az storage account keys list -n savmapps -g rg-vmspot --query [0].value) --expiry  $(date -u -d "7 days" '+%Y-%m-%dT%H:%MZ') --permissions r -o tsv)
   ```

#### Publish the packaged workload and get a valid SAS uri

1. Publish the version **0.1.0** of the orchestration worker app

   ```bash
   az sig gallery-application version create --version-name 0.1.0 --application-name app --gallery-name ga --location "West Central Us" --resource-group rg-vmspot --package-file-link $saWorkerUri --install-command "mkdir -p /usr/share/worker-0.1.0 && tar -oxzf ./app -C /usr/share/worker-0.1.0 && cp /usr/share/worker-0.1.0/orchestrate.sh . && ./orchestrate.sh -i" --remove-command "./orchestrate.sh -u"
   ```

#### Set a VM application to the Spot VM

1. Assign the **worker 0.1.0** VM app to the Spot VM

   ```bash
   az vm application set --resource-group rg-vmspot --name vm-spot --app-version-ids $(az sig gallery-application version show --version-name 0.1.0 --application-name app --gallery-name ga --resource-group rg-vmspot --query id -o tsv)
   ```

#### Simulate en Eviction Event

1. Test your Spot VM and see how the interruptible workload respond to disruption

   ```bash
   az rest --method post --uri /subscriptions/{subscriptionId}/resourceGroups/rg-vmspot/providers/Microsoft.Compute/virtualMachines/vm-spot/simulateEviction?api-version=2020-06-01
   ```

1. Validate the interruptible workload gracefully shutdown by looking at the tracing data in Azure Monitor

   ```bash
   az monitor app-insights query -g rg-vmspot --app aiworkload --analytics-query 'traces | project timestamp, message | order by timestamp' --offset 0h10m --query "tables[0].rows"
   ```

   > **Warning**
   > It takes few minutes to dump the traced messages into log analytics. You could choose waiting some time before executing the query or just go to Azure Portal at your Application Insights Live Metrics instance.

1. Start the stopped Spot VM.

   ```bash
   az vm start --resource-group rg-vmspot --name vm-spot
   ```

   > **Note**
   > If you remote ssh the VM you could confirm the Interruptible Workload service is now started and running again.

#### Clean up

1. Delete the Azure Spot VM resource group

   ```bash
   az group delete -n rg-vmspot -y
   ```

### Toublehshooting

#### Remote ssh using Bastion into the Spot VM

1. SSH into the new Spot VM. For detailed steps please take a look at [Connect to a Linux VM](https://docs.microsoft.com/azure/virtual-machines/linux-vm-connect?tabs=Linux)

   ```bash
   az network bastion ssh -n bh -g rg-vmspot --username azureuser --ssh-key ~/.ssh/opsvmspots.pem --auth-type ssh-key --target-resource-id $(az vm show -g rg-vmspot -n vm-spot --query id -o tsv)
   ```

#### Manually copy the **worker-0.1.0.tar.gz** file into the Spot VM

1. Open a tunnel using Bastion between your machine and the remote Spot VM

   ```bash
   az network bastion tunnel -n bh -g rg-vmspot --target-resource-id $(az vm show -g rg-vmspot -n vm-spot --query id -o tsv) --resource-port 22 --port 50022
   ```

1. Copy the file using ssh copy

   ```bash
   scp -i ~/.ssh/opsvmspots.pem -P 50022 src/bin/Release/net6.0/worker-0.1.0.tar.gz azureuser@localhost:~/.
   ```

#### Check the interruptible workload status within the Spot VM

1. you can remote ssh by using the section above and then execute the following command

   ```bash
   sudo systemctl status interruptible-workload
   ```

   After the new VM App version installation is complete if you ssh remote you could execute you could get a status outcome similar to one shown below

   ![Interruptible Workload service status.](./output.png)

[Azure Spot advisor]: https://azure.microsoft.com/pricing/spot-advisor
[Azure Retail Prices API]: https://docs.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices
[Azure Scheduled Events]: https://docs.microsoft.com/azure/virtual-machines/linux/scheduled-events
