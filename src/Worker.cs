using Azure.Storage.Queues;
using Microsoft.ApplicationInsights;

namespace interruptible_workload;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly TelemetryClient _telemetryClient;
    private readonly QueueClient _queueClient;

    public Worker(
        ILogger<Worker> logger,
        TelemetryClient tc,
        QueueClient queueClient)
    {
        _logger = logger;
        _telemetryClient = tc;
        _queueClient = queueClient;
    }

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        // Recover
        // In this architecture it is reached right after the VM is started for
        // the first time or after eviction (redeployed or restarted).
        // No other services are getting started until this run to completion 
        // and it is critical to start querying the Azure Event Scheduled as soon as 
        // possible (remember the up to 30 sec notice) taking into consideration that
        // a Spot Virtual Machine can be evicted right after it has been started.
        // Therefore, recovering should execute limited to short running tasks.
        _logger.LogInformation("* -> [recover] ...");
        await base.StartAsync(cancellationToken);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Resume
        // After this point the appliation must be ready to start processing 
        // messages after doing a best effort to recover from a previous checkpoint
        _logger.LogInformation("* -> [recover] -> [resume] -> [start] -> ...");
        _telemetryClient.TrackTrace("Interruptible workload about to start processing...");
        // Start processing
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _logger.LogInformation("attemp to receive messages from queue");
                foreach (var message in (await _queueClient.ReceiveMessagesAsync(
                    maxMessages: 10,
                    cancellationToken: stoppingToken)).Value)
                {
                    _logger.LogInformation("processing message: {MessageId}", message.MessageId);
                    await _queueClient.DeleteMessageAsync(
                      message.MessageId,
                      message.PopReceipt,
                      stoppingToken);
                    _logger.LogInformation("message deleted: {MessageId}", message.MessageId);
                }
            }
            catch (TaskCanceledException)
            {
                _logger.LogWarning("attempting graceful shutdown...");
                return;
            }

            await Task.Delay(1000, stoppingToken);
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _telemetryClient.TrackTrace("Eviction signal received at worker level");
        // Shutdown
        // An eviction notice been detected. For more information about how to
        // implement this dectection, please take a look at the ScheduledEvents 
        // background service.
        // At this point Azure infrastructure is claiming for this Spot VM instance.
        // In this reference implementation, you are querying every 1 sec 
        // the Azure Scheduled Event metadata endpoint, and eviction notices
        // are expected to be scheduled with up to up to 30 seconds in advance. 
        // Ensure you quicly stop the application within a reasonable amount 
        // of time to prevent from being forcedly shutdown.
        _logger.LogInformation("* -> [recover] -> [resume] -> [start] -> [shutdown] -> *");
        await base.StopAsync(cancellationToken);
        _telemetryClient.TrackTrace("🎉 gracefull shutdown OK...");
        _telemetryClient.Flush();
        Task.Delay(5000).Wait();
    }
}
