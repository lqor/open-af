public without sharing class AgentToolContext {
    public Id runId { get; private set; }
    public Id conversationId { get; private set; }
    public Id scheduledTaskId { get; private set; }
    public AgentConfig__c config { get; private set; }

    public AgentToolContext(Id runId, Id conversationId, Id scheduledTaskId, AgentConfig__c config) {
        this.runId = runId;
        this.conversationId = conversationId;
        this.scheduledTaskId = scheduledTaskId;
        this.config = config;
    }
}
