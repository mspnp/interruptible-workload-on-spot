namespace interruptible_workload;

public class ScheduledEvents: BackgroundService
{
    private readonly IHostApplicationLifetime _lifetime;
    private readonly ILogger<ScheduledEvents> _logger;
    private readonly IScheduledEventsService _scheduledEventsService;

    public ScheduledEvents(
        IHostApplicationLifetime lifetime,
        ILogger<ScheduledEvents> logger,
        IScheduledEventsService scheduledEventsService)
    {
        _lifetime = lifetime;
        _logger = logger;
        _scheduledEventsService = scheduledEventsService;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("endpoint query stated executing");
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (await _scheduledEventsService.GetScheduledEventsAsync(stoppingToken) is ScheduledEventsDocument scheduledEvents
                    && (scheduledEvents?.Events) != null
                    && scheduledEvents.Events.Any(e => 
                        e.EventType == "Preempt" 
                        && e.Resources.Any(r => r == "vm-spot")))
                {
                    _logger.LogWarning("eviction noticed");
                    _lifetime.StopApplication();
                    return;
                }
            }
            catch
            {
            }

            await Task.Delay(1000, stoppingToken);
        }
    }
}
