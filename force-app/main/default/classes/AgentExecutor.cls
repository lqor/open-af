public without sharing class AgentExecutor implements Queueable, Database.AllowsCallouts {
    private final Id runId;

    public AgentExecutor(Id runId) {
        this.runId = runId;
    }

    public void execute(QueueableContext context) {
        new AgentRuntime().executeRun(runId);
    }
}
