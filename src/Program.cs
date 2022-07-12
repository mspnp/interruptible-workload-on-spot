using Azure.Identity;
using Azure.Storage.Queues;
using Microsoft.Extensions.Azure;
using interruptible_workload;

IHost host = Host.CreateDefaultBuilder(args)
    .ConfigureServices(services =>
    {
        services.AddHostedService<Worker>();
        services.AddAzureClients(builder =>
        {
          builder.AddClient<QueueClient, QueueClientOptions>((_, _, _) =>
            new QueueClient(
              new Uri($"https://saworkloadqueue.queue.core.windows.net/messaging"),
              new DefaultAzureCredential()));
        });

        services.AddHostedService<ScheduledEvents>();
        services.AddHttpClient<ScheduledEvents>();
    })
    .Build();

await host.RunAsync();
