public without sharing class OpenAfController {
    @AuraEnabled(cacheable=true)
    public static OpenAfModels.BootstrapData getBootstrap() {
        OpenAfModels.BootstrapData data = new OpenAfModels.BootstrapData();
        data.currentConversationId = null;
        data.configs = AgentConfigService.getConfigViews();
        data.conversations = getConversations();
        data.conversationState = null;
        return data;
    }

    @AuraEnabled
    public static Id createConversation(String name, Id configId) {
        AgentConfig__c config = AgentConfigService.getConfig(configId);
        Conversation__c conversation = new Conversation__c(
            Name = String.isBlank(name) ? 'Conversation ' + Date.today().format() : name.trim(),
            AgentConfig__c = config.Id,
            Status__c = 'Open'
        );
        insert conversation;
        return conversation.Id;
    }

    @AuraEnabled
    public static OpenAfModels.RunResult submitPrompt(OpenAfModels.RunRequest request) {
        if (request == null || String.isBlank(request.prompt)) {
            throw new AuraHandledException('A prompt is required.');
        }

        Id conversationId = request.conversationId;
        if (conversationId == null) {
            conversationId = createConversation('General', request.configId);
        }

        AgentConfig__c config = AgentConfigService.getConfig(request.configId);
        Run__c runRecord = new Run__c(
            Conversation__c = conversationId,
            AgentConfig__c = config.Id,
            ScheduledTask__c = request.scheduledTaskId,
            UserPrompt__c = request.prompt,
            Status__c = 'Queued',
            TriggerType__c = String.isBlank(request.triggerType) ? 'chat' : request.triggerType
        );
        insert runRecord;
        runRecord.AsyncJobId__c = System.enqueueJob(new AgentExecutor(runRecord.Id));
        update runRecord;
        return AgentRuntime.getRunResult(runRecord.Id);
    }

    @AuraEnabled
    public static OpenAfModels.ConversationState getConversationState(Id conversationId) {
        Conversation__c conversation = [
            SELECT Id, Name
            FROM Conversation__c
            WHERE Id = :conversationId
            LIMIT 1
        ];

        OpenAfModels.ConversationState state = new OpenAfModels.ConversationState();
        state.conversationId = conversation.Id;
        state.conversationName = conversation.Name;

        List<Message__c> messages = [
            SELECT Id, Content__c, Role__c, Sequence__c, ToolCallId__c, ToolName__c, CreatedDate
            FROM Message__c
            WHERE Conversation__c = :conversationId
            ORDER BY Sequence__c ASC, CreatedDate ASC
            LIMIT 200
        ];
        for (Message__c row : messages) {
            OpenAfModels.MessageView view = new OpenAfModels.MessageView();
            view.id = row.Id;
            view.role = row.Role__c;
            view.content = row.Content__c;
            view.sequence = row.Sequence__c;
            view.toolCallId = row.ToolCallId__c;
            view.toolName = row.ToolName__c;
            view.createdDate = row.CreatedDate;
            state.messages.add(view);
        }

        List<Run__c> runs = [
            SELECT Id, Status__c, FinalResponse__c, Error__c, CreatedDate
            FROM Run__c
            WHERE Conversation__c = :conversationId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!runs.isEmpty()) {
            Run__c currentRun = runs[0];
            state.currentRunId = currentRun.Id;
            state.runStatus = currentRun.Status__c;
            state.finalResponse = currentRun.FinalResponse__c;
            state.error = currentRun.Error__c;

            for (ToolExecution__c execution : [
                SELECT Id, ToolName__c, Status__c, InputJson__c, OutputJson__c, Error__c, Sequence__c, CreatedDate
                FROM ToolExecution__c
                WHERE Run__c = :currentRun.Id
                ORDER BY Sequence__c ASC, CreatedDate ASC
                LIMIT 200
            ]) {
                OpenAfModels.ToolExecutionView toolView = new OpenAfModels.ToolExecutionView();
                toolView.id = execution.Id;
                toolView.toolName = execution.ToolName__c;
                toolView.status = execution.Status__c;
                toolView.inputJson = execution.InputJson__c;
                toolView.outputJson = execution.OutputJson__c;
                toolView.error = execution.Error__c;
                toolView.sequence = execution.Sequence__c;
                toolView.createdDate = execution.CreatedDate;
                state.toolExecutions.add(toolView);
            }
        }

        return state;
    }

    @AuraEnabled
    public static OpenAfModels.RunResult cancelRun(Id runId) {
        if (runId == null) {
            throw new AuraHandledException('A run id is required.');
        }

        Run__c runRecord = [
            SELECT Id, Status__c, AsyncJobId__c, CancelRequested__c, CompletedAt__c, Error__c
            FROM Run__c
            WHERE Id = :runId
            LIMIT 1
        ];
        if (runRecord.Status__c != 'Queued' && runRecord.Status__c != 'Running') {
            return AgentRuntime.getRunResult(runId);
        }

        runRecord.CancelRequested__c = true;
        Boolean cancelledNow = false;
        if (!String.isBlank(runRecord.AsyncJobId__c)) {
            try {
                System.abortJob(runRecord.AsyncJobId__c);
                cancelledNow = true;
            } catch (Exception error) {
                cancelledNow = false;
            }
        }

        if (cancelledNow || runRecord.Status__c == 'Queued') {
            runRecord.Status__c = 'Cancelled';
            runRecord.CompletedAt__c = System.now();
            runRecord.Error__c = 'Cancelled by user.';
        }
        update runRecord;
        return AgentRuntime.getRunResult(runRecord.Id);
    }

    @AuraEnabled(cacheable=true)
    public static List<OpenAfModels.ConfigView> getConfigs() {
        return AgentConfigService.getConfigViews();
    }

    @AuraEnabled(cacheable=true)
    public static List<OpenAfModels.ConversationSummary> getConversations() {
        List<OpenAfModels.ConversationSummary> summaries = new List<OpenAfModels.ConversationSummary>();
        for (Conversation__c conv : [
            SELECT Id, Name, Status__c, CreatedDate, LastModifiedDate
            FROM Conversation__c
            ORDER BY LastModifiedDate DESC
            LIMIT 50
        ]) {
            OpenAfModels.ConversationSummary summary = new OpenAfModels.ConversationSummary();
            summary.id = conv.Id;
            summary.name = conv.Name;
            summary.status = conv.Status__c;
            summary.createdDate = conv.CreatedDate;
            summary.lastModifiedDate = conv.LastModifiedDate;
            summaries.add(summary);
        }
        return summaries;
    }

    @AuraEnabled
    public static void deleteConversation(Id conversationId) {
        if (conversationId == null) {
            throw new AuraHandledException('Conversation ID is required.');
        }
        // Cascade delete: tool executions → runs → messages → conversation
        List<Run__c> runs = [SELECT Id FROM Run__c WHERE Conversation__c = :conversationId];
        Set<Id> runIds = new Set<Id>();
        for (Run__c r : runs) {
            runIds.add(r.Id);
        }
        List<ToolExecution__c> toolExecs = runIds.isEmpty()
            ? new List<ToolExecution__c>()
            : [SELECT Id FROM ToolExecution__c WHERE Run__c IN :runIds];
        List<Message__c> messages = [SELECT Id FROM Message__c WHERE Conversation__c = :conversationId];

        delete toolExecs;
        delete runs;
        delete messages;

        Conversation__c conv = [SELECT Id FROM Conversation__c WHERE Id = :conversationId LIMIT 1];
        delete conv;
    }

    @AuraEnabled
    public static OpenAfModels.ConfigView saveConfig(OpenAfModels.ConfigInput input) {
        return AgentConfigService.toView(AgentConfigService.saveConfig(input));
    }

    @AuraEnabled(cacheable=true)
    public static List<OpenAfModels.ScheduledTaskView> getScheduledTasks() {
        return AgentScheduleService.getScheduledTaskViews();
    }

    @AuraEnabled
    public static OpenAfModels.ScheduledTaskView saveScheduledTask(OpenAfModels.ScheduledTaskInput input) {
        ScheduledTask__c task = AgentScheduleService.saveScheduledTask(input);
        for (OpenAfModels.ScheduledTaskView view : AgentScheduleService.getScheduledTaskViews()) {
            if (view.id == task.Id) {
                return view;
            }
        }
        return null;
    }

    @AuraEnabled
    public static void cancelScheduledTask(Id taskId) {
        AgentScheduleService.cancelScheduledTask(taskId);
    }
}
