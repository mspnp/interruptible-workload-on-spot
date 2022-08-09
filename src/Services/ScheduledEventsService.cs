namespace interruptible_workload;

using System;
using System.Collections.Generic;
using System.Net.Http.Json;

public interface IScheduledEventsService
{
   Task<ScheduledEventsDocument?> GetScheduledEventsAsync(CancellationToken cancellationToken = default);
}

public class ScheduledEventsDocument
{
    public int? DocumentIncarnation { get; set; }
    public List<ScheduledEvent>? Events { get; set; }
}

public class ScheduledEvent
{
    public string? EventId { get; set; }
    public string? EventStatus { get; set; }
    public string? EventType { get; set; }
    public string? ResourceType { get; set; }
    public List<string>? Resources { get; set; }
    public String? NotBefore { get; set; }
    public string? EventSource { get; set; }
    public string? Description { get; set; }
    public int? DurationInSeconds { get; set; }
}

public class ScheduledEventsService: IScheduledEventsService
{
    private readonly ILogger<ScheduledEvents> _logger;
    private readonly HttpClient _httpClient;

    public ScheduledEventsService(
        ILogger<ScheduledEvents> logger,
        HttpClient httpClient)
    {
        _logger = logger;
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri("http://169.254.169.254/metadata/");
        _httpClient.DefaultRequestHeaders.Add("Metadata", "true");
    }

   public async Task<ScheduledEventsDocument?> GetScheduledEventsAsync(CancellationToken cancellationToken = default)
    => (await _httpClient.GetFromJsonAsync<ScheduledEventsDocument>("scheduledevents?api-version=2020-07-01", cancellationToken));
}
