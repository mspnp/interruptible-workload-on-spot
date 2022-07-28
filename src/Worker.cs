namespace interruptible_workload;

using Azure.Storage.Queues;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly QueueClient _queueClient;

    public Worker(
        ILogger<Worker> logger,
        QueueClient queueClient)
    {
        _logger = logger;
        _queueClient = queueClient;
    }

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("[recover] ->");
        await base.StartAsync(cancellationToken);
        _logger.LogInformation("[resume] ->");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[start] ->");
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(1000, stoppingToken);
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
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("[shutdown] ->");
        await base.StopAsync(cancellationToken);
        _logger.LogInformation("gracefull shutdown OK...");
    }
}