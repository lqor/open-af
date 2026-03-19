public class OpenAfModels {
    public class RunRequest {
        @AuraEnabled public Id conversationId { get; set; }
        @AuraEnabled public Id configId { get; set; }
        @AuraEnabled public String prompt { get; set; }
        @AuraEnabled public Id scheduledTaskId { get; set; }
        @AuraEnabled public String triggerType { get; set; }
    }

    public class RunResult {
        @AuraEnabled public Id runId { get; set; }
        @AuraEnabled public Id conversationId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String finalResponse { get; set; }
        @AuraEnabled public String error { get; set; }
    }

    public class ToolCall {
        public String id { get; set; }
        public String name { get; set; }
        public String inputJson { get; set; }
    }

    public class ProviderMessage {
        public String role { get; set; }
        public String content { get; set; }
        public String toolCallId { get; set; }
        public String toolName { get; set; }
        public List<ToolCall> toolCalls { get; set; }

        public ProviderMessage() {
            this.toolCalls = new List<ToolCall>();
        }
    }

    public class ProviderToolDefinition {
        public String name { get; set; }
        public String description { get; set; }
        public Object inputSchema { get; set; }
    }

    public class ProviderRequest {
        public String providerName { get; set; }
        public String model { get; set; }
        public String systemPrompt { get; set; }
        public Integer maxTokens { get; set; }
        public List<ProviderMessage> messages { get; set; }
        public List<ProviderToolDefinition> tools { get; set; }

        public ProviderRequest() {
            this.messages = new List<ProviderMessage>();
            this.tools = new List<ProviderToolDefinition>();
            this.maxTokens = 1024;
        }
    }

    public class ProviderResponse {
        public String assistantText { get; set; }
        public List<ToolCall> toolCalls { get; set; }
        public String rawResponse { get; set; }

        public ProviderResponse() {
            this.toolCalls = new List<ToolCall>();
        }
    }

    public class MessageView {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String role { get; set; }
        @AuraEnabled public String content { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public String toolCallId { get; set; }
        @AuraEnabled public String toolName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class ToolExecutionView {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String toolName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String inputJson { get; set; }
        @AuraEnabled public String outputJson { get; set; }
        @AuraEnabled public String error { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class ConversationSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
    }

    public class ConversationState {
        @AuraEnabled public Id conversationId { get; set; }
        @AuraEnabled public String conversationName { get; set; }
        @AuraEnabled public Id currentRunId { get; set; }
        @AuraEnabled public String runStatus { get; set; }
        @AuraEnabled public String finalResponse { get; set; }
        @AuraEnabled public String error { get; set; }
        @AuraEnabled public List<MessageView> messages { get; set; }
        @AuraEnabled public List<ToolExecutionView> toolExecutions { get; set; }

        public ConversationState() {
            this.messages = new List<MessageView>();
            this.toolExecutions = new List<ToolExecutionView>();
        }
    }

    public class ConfigInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String systemPrompt { get; set; }
        @AuraEnabled public String enabledTools { get; set; }
        @AuraEnabled public Integer maxTurns { get; set; }
    }

    public class ConfigView {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String systemPrompt { get; set; }
        @AuraEnabled public String enabledTools { get; set; }
        @AuraEnabled public Decimal maxTurns { get; set; }
        @AuraEnabled public String label { get; set; }
    }

    public class ScheduledTaskInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Id agentConfigId { get; set; }
        @AuraEnabled public String prompt { get; set; }
        @AuraEnabled public Boolean isRecurring { get; set; }
        @AuraEnabled public String cronExpression { get; set; }
        @AuraEnabled public Datetime oneOffRunAt { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    public class ScheduledTaskView {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Id agentConfigId { get; set; }
        @AuraEnabled public String prompt { get; set; }
        @AuraEnabled public Boolean isRecurring { get; set; }
        @AuraEnabled public String cronExpression { get; set; }
        @AuraEnabled public Datetime oneOffRunAt { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String jobId { get; set; }
        @AuraEnabled public Datetime lastRunAt { get; set; }
        @AuraEnabled public String lastRunStatus { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class BootstrapData {
        @AuraEnabled public Id currentConversationId { get; set; }
        @AuraEnabled public List<ConversationSummary> conversations { get; set; }
        @AuraEnabled public List<ConfigView> configs { get; set; }
        @AuraEnabled public ConversationState conversationState { get; set; }

        public BootstrapData() {
            this.conversations = new List<ConversationSummary>();
            this.configs = new List<ConfigView>();
        }
    }
}
