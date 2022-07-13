namespace interruptible_workload;

using Azure.Storage.Queues;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly QueueClient _queueClient;

    public Worker(ILogger<Worker> logger, QueueClient queueClient)
    {
        _logger = logger;
        _queueClient = queueClient;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            _logger.LogInformation("Worker running at: {time}", DateTimeOffset.Now);
            await Task.Delay(1000, stoppingToken);

            foreach (var message in (await _queueClient.ReceiveMessagesAsync(maxMessages: 10)).Value)
            {
                Console.WriteLine($"Message: {message.Body}");

                await _queueClient.DeleteMessageAsync(
                  message.MessageId,
                  message.PopReceipt);
            }
        }
    }
}
