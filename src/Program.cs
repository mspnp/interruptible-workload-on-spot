using Azure.Identity;
using Azure.Storage;
using Azure.Storage.Queues;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.ApplicationInsights.Extensibility.Implementation;
using Azure.Storage;
using Microsoft.Extensions.Azure;
using interruptible_workload;

IHost host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((hostContext, services) =>
    {
        services.AddHostedService<Worker>();
        // configure telemetry
        services.Configure<TelemetryConfiguration>(
          config => {
            if (hostContext.HostingEnvironment.IsDevelopment())
            {
              TelemetryDebugWriter.IsTracingDisabled = false;
              config.DisableTelemetry = false;
            }
            else
            {
              TelemetryDebugWriter.IsTracingDisabled = false;
              config.DisableTelemetry = false;
            }
          });

        services.AddApplicationInsightsTelemetryWorkerService();

        services.AddAzureClients(builder =>
        {
          builder.AddClient<QueueClient, QueueClientOptions>((_, _, _)
            => hostContext.HostingEnvironment.IsDevelopment() ?
              new QueueClient(
                new Uri("https://127.0.0.1:10001/devstoreaccount1/messaging"),
                new StorageSharedKeyCredential("devstoreaccount1", "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==")) :
              new QueueClient(
                new Uri($"https://saworkloadqueue.queue.core.windows.net/messaging"),
                new DefaultAzureCredential()));
        });

        if (hostContext.HostingEnvironment.IsDevelopment())
        {
          services.AddSingleton<IScheduledEventsService, ScheduledEventsServiceEmulator>();
        }
        else
        {
          services.AddSingleton<IScheduledEventsService, ScheduledEventsService>();
        }

        services.AddHostedService<ScheduledEvents>();
        services.AddHttpClient<ScheduledEvents>();
    })
    .Build();
// Start processing
await host.RunAsync();
