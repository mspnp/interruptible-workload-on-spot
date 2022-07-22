namespace interruptible_workload;

using System;
using System.Collections.Generic;
using System.Net.Http.Json;

public class ScheduledEventsDocument
{
    public string? DocumentIncarnation { get; set; }
    public List<ScheduledEvent>? Events { get; set; }
}

public class ScheduledEvent
{
    public string? EventId { get; set; }
    public string? EventStatus { get; set; }
    public string? EventType { get; set; }
    public string? ResourceType { get; set; }
    public List<string>? Resources { get; set; }
    public DateTime? NotBefore { get; set; }
}

public class ScheduledEvents: BackgroundService
{
    private readonly IHostApplicationLifetime _lifetime;
    private readonly ILogger<ScheduledEvents> _logger;
    private readonly HttpClient _httpClient;

    public ScheduledEvents(
        IHostApplicationLifetime lifetime,
        ILogger<ScheduledEvents> logger,
        HttpClient httpClient)
    {
        _lifetime = lifetime;
        _logger = logger;
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri("http://169.254.169.254/metadata/");
        _httpClient.DefaultRequestHeaders.Add("Metadata", "true");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("ScheduledEvents running at: {time}", DateTimeOffset.UtcNow);

        while (!stoppingToken.IsCancellationRequested)
        {
            Console.WriteLine("ScheduledEvents: {_httpClient.BaseAddress}");
            try
            {
              if ((await _httpClient.GetFromJsonAsync<ScheduledEventsDocument>("scheduledevents?api-version=2020-07-01")
                 is ScheduledEventsDocument scheduledEvents)
                 && scheduledEvents?.Events != null
                 && scheduledEvents.Events.Any(e => e.EventType == "Preempt" && e.Resources.Any(r => r == "vm-spot")))
              {
                  Console.WriteLine($"Eviction detected");
                  _lifetime.StopApplication();
              }
              else
              {
                  Console.WriteLine($"Eviction not detected");
              }
            }
            catch {}

            await Task.Delay(1000, stoppingToken);
        }
    }
}
