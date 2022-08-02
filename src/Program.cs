using Azure.Identity;
using Azure.Storage;
using Azure.Storage.Queues;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.ApplicationInsights.Extensibility.Implementation;
using Microsoft.Extensions.Azure;
using interruptible_workload;

IHost host = Host.CreateDefaultBuilder(args)
    .ConfigureServices(services =>
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
          builder.AddClient<QueueClient, QueueClientOptions>((_, _, _) =>
            new QueueClient(
              new Uri($"https://saworkloadqueue.queue.core.windows.net/messaging"),
              new DefaultAzureCredential()));
        });

        services.AddSingleton<IScheduledEventsService, ScheduledEventsService>();
        services.AddHostedService<ScheduledEvents>();
        services.AddHttpClient<ScheduledEvents>();
    })
    .Build();
// Start processing
await host.RunAsync();
