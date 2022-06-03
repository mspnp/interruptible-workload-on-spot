namespace interruptible_workload;

using Azure.Identity;
using Azure.Storage.Queues;

public class Worker : BackgroundService
{
    private readonly static string s_storageAccountName = "saworkloadqueue";
    private readonly static string s_queueName = "messaging";
    private readonly ILogger<Worker> _logger;

    public Worker(ILogger<Worker> logger)
    {
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            _logger.LogInformation("Worker running at: {time}", DateTimeOffset.Now);
            await Task.Delay(1000, stoppingToken);

            var queueClient = new QueueClient(
              new Uri($"https://{s_storageAccountName}.queue.core.windows.net/{s_queueName}"),
              new DefaultAzureCredential());

            foreach (var message in (await queueClient.ReceiveMessagesAsync(maxMessages: 10)).Value)
            {
                Console.WriteLine($"Message: {message.Body}");

                await queueClient.DeleteMessageAsync(
                  message.MessageId,
                  message.PopReceipt);
            }
        }
    }
}
