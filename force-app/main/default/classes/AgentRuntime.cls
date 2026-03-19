public without sharing class AgentRuntime {
    public class RuntimeException extends Exception {}
    public class RunCancelledException extends Exception {}

    public OpenAfModels.RunResult executeRun(Id runId) {
        Run__c runRecord = [
            SELECT Id, Conversation__c, AgentConfig__c, ScheduledTask__c, UserPrompt__c, Status__c, TriggerType__c, CancelRequested__c
            FROM Run__c
            WHERE Id = :runId
            LIMIT 1
        ];
        AgentConfig__c config = AgentConfigService.getConfig(runRecord.AgentConfig__c);
        AgentProvider provider = AgentProviderFactory.getProvider(config);

        Integer nextSequence = getNextSequence(runRecord.Conversation__c);
        List<Message__c> pendingMessages = new List<Message__c>();
        List<ToolExecution__c> pendingToolExecutions = new List<ToolExecution__c>();

        pendingMessages.add(new Message__c(
            Conversation__c = runRecord.Conversation__c,
            Run__c = runRecord.Id,
            Role__c = 'user',
            Content__c = runRecord.UserPrompt__c,
            Sequence__c = nextSequence
        ));
        nextSequence++;

        List<Message__c> persistedMessages = [
            SELECT Id, Content__c, Role__c, ToolCallId__c, ToolName__c, Sequence__c
            FROM Message__c
            WHERE Conversation__c = :runRecord.Conversation__c
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];

        List<OpenAfModels.ProviderMessage> workingMessages = toProviderMessages(persistedMessages);
        workingMessages.add(toProviderMessage(pendingMessages[0]));
        Set<String> enabledTools = AgentConfigService.enabledToolSet(config);
        List<OpenAfModels.ProviderToolDefinition> toolDefinitions = AgentToolRegistry.describeTools(enabledTools);
        Integer maxTurns = config.MaxTurns__c == null ? 5 : Integer.valueOf(config.MaxTurns__c.intValue());
        Integer nextToolSequence = getNextToolSequence(runRecord.Id);
        String finalAssistantText;

        runRecord.Status__c = 'Running';
        runRecord.StartedAt__c = System.now();

        try {
            for (Integer turn = 1; turn <= maxTurns; turn++) {
                throwIfCancellationRequested(runRecord.Id, runRecord.CancelRequested__c);

                OpenAfModels.ProviderRequest request = new OpenAfModels.ProviderRequest();
                request.providerName = provider.getName();
                request.model = config.Model__c;
                request.systemPrompt = config.SystemPrompt__c;
                request.maxTokens=1024;
                request.messages.addAll(workingMessages);
                request.tools.addAll(toolDefinitions);

                OpenAfModels.ProviderResponse response = provider.invoke(request);
                throwIfCancellationRequested(runRecord.Id, false);
                String assistantText = String.isBlank(response.assistantText)
                    ? (response.toolCalls.isEmpty() ? '' : 'Using tools: ' + getToolCallSummary(response.toolCalls))
                    : response.assistantText;
                finalAssistantText = String.isBlank(response.assistantText) ? finalAssistantText : response.assistantText;

                Message__c assistantRecord = new Message__c(
                    Conversation__c = runRecord.Conversation__c,
                    Run__c = runRecord.Id,
                    Role__c = 'assistant',
                    Content__c = assistantText,
                    Sequence__c = nextSequence
                );
                pendingMessages.add(assistantRecord);
                nextSequence++;

                OpenAfModels.ProviderMessage assistantMessage = new OpenAfModels.ProviderMessage();
                assistantMessage.role = 'assistant';
                assistantMessage.content = assistantText;
                assistantMessage.toolCalls.addAll(response.toolCalls);
                workingMessages.add(assistantMessage);

                if (response.toolCalls.isEmpty()) {
                    runRecord.TurnCount__c = turn;
                    break;
                }

                for (OpenAfModels.ToolCall toolCall : response.toolCalls) {
                    throwIfCancellationRequested(runRecord.Id, false);
                    ToolExecution__c execution = new ToolExecution__c(
                        Run__c = runRecord.Id,
                        ToolName__c = toolCall.name,
                        InputJson__c = toolCall.inputJson,
                        Status__c = 'Pending',
                        Sequence__c = nextToolSequence
                    );
                    pendingToolExecutions.add(execution);
                    nextToolSequence++;

                    String toolOutput;
                    try {
                        if (!enabledTools.contains(toolCall.name)) {
                            throw new AgentToolRegistry.ToolException('Tool is disabled in the active config: ' + toolCall.name);
                        }
                        AgentTool tool = AgentToolRegistry.requireTool(toolCall.name);
                        toolOutput = tool.invoke(toolCall.inputJson, new AgentToolContext(runRecord.Id, runRecord.Conversation__c, runRecord.ScheduledTask__c, config));
                        execution.Status__c = 'Completed';
                        execution.OutputJson__c = toolOutput;
                    } catch (Exception toolError) {
                        toolOutput = JSON.serialize(new Map<String, Object>{
                            'success' => false,
                            'error' => toolError.getMessage()
                        });
                        execution.Status__c = 'Failed';
                        execution.Error__c = toolError.getMessage();
                        execution.OutputJson__c = toolOutput;
                        // Do NOT set runRecord.Status__c = 'Failed' — tool errors are handled gracefully
                    }

                    Message__c toolRecord = new Message__c(
                        Conversation__c = runRecord.Conversation__c,
                        Run__c = runRecord.Id,
                        Role__c = 'tool',
                        Content__c = toolOutput,
                        ToolCallId__c = toolCall.id,
                        ToolName__c = toolCall.name,
                        Sequence__c = nextSequence
                    );
                    pendingMessages.add(toolRecord);
                    nextSequence++;

                    OpenAfModels.ProviderMessage toolMessage = new OpenAfModels.ProviderMessage();
                    toolMessage.role = 'tool';
                    toolMessage.toolCallId = toolCall.id;
                    toolMessage.toolName = toolCall.name;
                    toolMessage.content = toolOutput;
                    workingMessages.add(toolMessage);
                }
                runRecord.TurnCount__c = turn;

                // Persist this turn's results BEFORE publishing the event
                update runRecord;
                if (!pendingMessages.isEmpty()) {
                    insert pendingMessages;
                }
                if (!pendingToolExecutions.isEmpty()) {
                    insert pendingToolExecutions;
                }
                pendingMessages.clear();
                pendingToolExecutions.clear();
            }

            runRecord.Status__c = 'Completed';
            runRecord.FinalResponse__c = finalAssistantText;
            runRecord.CompletedAt__c = System.now();
            runRecord.Error__c = null;
            update runRecord;

            if (runRecord.ScheduledTask__c != null) {
                AgentScheduleService.markTaskRun(runRecord.ScheduledTask__c, 'Completed');
            }
        } catch (RunCancelledException cancelled) {
            runRecord.Status__c = 'Cancelled';
            runRecord.Error__c = cancelled.getMessage();
            runRecord.CompletedAt__c = System.now();
            runRecord.FinalResponse__c = null;
            update runRecord;
        } catch (Exception error) {
            runRecord.Status__c = 'Failed';
            runRecord.Error__c = error.getMessage();
            runRecord.CompletedAt__c = System.now();
            update runRecord;

            if (runRecord.ScheduledTask__c != null) {
                AgentScheduleService.markTaskRun(runRecord.ScheduledTask__c, 'Failed');
            }
        }

        return getRunResult(runRecord.Id);
    }

    public static OpenAfModels.RunResult getRunResult(Id runId) {
        Run__c runRecord = [
            SELECT Id, Conversation__c, Status__c, FinalResponse__c, Error__c
            FROM Run__c
            WHERE Id = :runId
            LIMIT 1
        ];
        OpenAfModels.RunResult result = new OpenAfModels.RunResult();
        result.runId = runRecord.Id;
        result.conversationId = runRecord.Conversation__c;
        result.status = runRecord.Status__c;
        result.finalResponse = runRecord.FinalResponse__c;
        result.error = runRecord.Error__c;
        return result;
    }

    private static List<OpenAfModels.ProviderMessage> toProviderMessages(List<Message__c> rows) {
        List<OpenAfModels.ProviderMessage> messages = new List<OpenAfModels.ProviderMessage>();
        for (Integer index = 0; index < rows.size(); index++) {
            Message__c row = rows[index];
            if (row == null || row.Role__c == 'tool') {
                continue;
            }
            if (shouldSkipToolSummaryAssistant(rows, index)) {
                continue;
            }
            messages.add(toProviderMessage(row));
        }
        return messages;
    }

    private static OpenAfModels.ProviderMessage toProviderMessage(Message__c row) {
        OpenAfModels.ProviderMessage message = new OpenAfModels.ProviderMessage();
        message.role = row.Role__c;
        message.content = row.Content__c;
        message.toolCallId = row.ToolCallId__c;
        message.toolName = row.ToolName__c;
        return message;
    }

    private static Boolean shouldSkipToolSummaryAssistant(List<Message__c> rows, Integer index) {
        Message__c row = rows[index];
        if (row.Role__c != 'assistant' || String.isBlank(row.Content__c) || !row.Content__c.startsWith('Using tools:')) {
            return false;
        }
        Integer nextIndex = index + 1;
        return nextIndex < rows.size() && rows[nextIndex] != null && rows[nextIndex].Role__c == 'tool';
    }

    private static Integer getNextSequence(Id conversationId) {
        Decimal currentMax = 0;
        AggregateResult[] results = [
            SELECT MAX(Sequence__c) maxSequence
            FROM Message__c
            WHERE Conversation__c = :conversationId
        ];
        if (!results.isEmpty() && results[0].get('maxSequence') != null) {
            currentMax = (Decimal) results[0].get('maxSequence');
        }
        return Integer.valueOf(currentMax.intValue()) + 1;
    }

    private static Integer getNextToolSequence(Id runId) {
        Decimal currentMax = 0;
        AggregateResult[] results = [
            SELECT MAX(Sequence__c) maxSequence
            FROM ToolExecution__c
            WHERE Run__c = :runId
        ];
        if (!results.isEmpty() && results[0].get('maxSequence') != null) {
            currentMax = (Decimal) results[0].get('maxSequence');
        }
        return Integer.valueOf(currentMax.intValue()) + 1;
    }

    private static String getToolCallSummary(List<OpenAfModels.ToolCall> toolCalls) {
        List<String> names = new List<String>();
        for (OpenAfModels.ToolCall toolCall : toolCalls) {
            names.add(toolCall.name);
        }
        return String.join(names, ', ');
    }

    private static void throwIfCancellationRequested(Id runId, Boolean alreadyKnownCancelled) {
        if (alreadyKnownCancelled) {
            throw new RunCancelledException('Cancelled by user.');
        }
        Run__c current = [
            SELECT CancelRequested__c
            FROM Run__c
            WHERE Id = :runId
            LIMIT 1
        ];
        if (current.CancelRequested__c) {
            throw new RunCancelledException('Cancelled by user.');
        }
    }
}
