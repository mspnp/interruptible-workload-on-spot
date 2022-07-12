namespace interruptible_workload;

public class ScheduledEvents: BackgroundService
{
    private readonly ILogger<ScheduledEvents> _logger;
    private readonly HttpClient _httpClient;

    public ScheduledEvents(
        ILogger<ScheduledEvents> logger,
        HttpClient httpClient)
    {
        _logger = logger;
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri("http://169.254.169.254/metadata/");
        _httpClient.DefaultRequestHeaders.Add("Metadata", "true");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("ScheduledEvents running at: {time}", DateTimeOffset.Now);
        while (!stoppingToken.IsCancellationRequested)
        {
            Console.WriteLine($"ScheduledEvents: {_httpClient.BaseAddress}");
            var response = await _httpClient.GetAsync("scheduledevents?api-version=2020-07-01");
            response.EnsureSuccessStatusCode();
            var content = await response.Content.ReadAsStringAsync();
            Console.WriteLine(content);
            await Task.Delay(10000, stoppingToken);
        }
    }
}
