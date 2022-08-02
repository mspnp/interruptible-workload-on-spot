namespace interruptible_workload;

public class ScheduledEventsServiceEmulator: IScheduledEventsService
{
    public int calls {get; set;} = 0;
    
    // At the call number eleven this method emulates an eviction notice by returning a scheduled event type Preempt
    public async Task<ScheduledEventsDocument?> GetScheduledEventsAsync(CancellationToken cancellationToken = default) 
        => calls++ > 10 ? 
            new ScheduledEventsDocument
            {
                Events = new List<ScheduledEvent> 
                {
                    new ScheduledEvent
                    {
                        EventType = "Preempt",
                        Resources = new List<string> { "vm-spot" }
                    }
                }
            } : null;
}
