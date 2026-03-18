@IsTest
private class AgentRuntimeAndScheduleTest {
    private static Integer runtimeInvocationCount = 0;
    private static Integer disabledInvocationCount = 0;
    private static Integer repeatedConversationInvocationCount = 0;

    private class RuntimeMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            runtimeInvocationCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (runtimeInvocationCount == 1) {
                response.setBody('{"choices":[{"message":{"content":"Checking Salesforce data.","tool_calls":[{"id":"call_1","type":"function","function":{"name":"runSoql","arguments":"{\\"query\\":\\"SELECT Id, Name FROM Account ORDER BY Name LIMIT 1\\"}"}}]}}]}');
            } else {
                response.setBody('{"choices":[{"message":{"content":"Found 1 account named Acme."}}]}');
            }
            return response;
        }
    }

    private class DisabledToolMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            disabledInvocationCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            if (disabledInvocationCount == 1) {
                response.setBody('{"choices":[{"message":{"content":"Trying a tool.","tool_calls":[{"id":"call_bad","type":"function","function":{"name":"runSoql","arguments":"{\\"query\\":\\"SELECT Id FROM Account LIMIT 1\\"}"}}]}}]}');
            } else {
                response.setBody('{"choices":[{"message":{"content":"Tool access was blocked, so I am done."}}]}');
            }
            return response;
        }
    }

    private class RepeatedConversationMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            repeatedConversationInvocationCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (repeatedConversationInvocationCount == 1) {
                response.setBody('{"choices":[{"message":{"content":"Checking Salesforce data.","tool_calls":[{"id":"call_first","type":"function","function":{"name":"runSoql","arguments":"{\\"query\\":\\"SELECT Id, Name FROM Account ORDER BY Name LIMIT 1\\"}"}}]}}]}');
            } else if (repeatedConversationInvocationCount == 2) {
                response.setBody('{"choices":[{"message":{"content":"The first account is Acme."}}]}');
            } else {
                response.setBody('{"choices":[{"message":{"content":"Your previous result was Acme, and I can still continue the conversation."}}]}');
            }
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        insert new Account(Name = 'Acme');
    }

    @IsTest
    static void submitPromptRunsToolLoopAndPersistsTrace() {
        ProviderSecrets.openAiKeyOverride = 'test-key';
        runtimeInvocationCount = 0;
        Test.setMock(HttpCalloutMock.class, new RuntimeMock());

        AgentConfig__c config = AgentConfigService.saveConfig(newConfigInput('openai', 'runSoql'));
        Id conversationId = OpenAfController.createConversation('Runtime Test', config.Id);
        OpenAfModels.RunRequest request = new OpenAfModels.RunRequest();
        request.conversationId = conversationId;
        request.configId = config.Id;
        request.prompt = 'Find the latest account.';
        request.triggerType = 'chat';

        Test.startTest();
        OpenAfController.submitPrompt(request);
        Test.stopTest();

        OpenAfModels.ConversationState state = OpenAfController.getConversationState(conversationId);
        System.assertEquals('Completed', state.runStatus);
        System.assertEquals(4, state.messages.size());
        System.assertEquals(1, state.toolExecutions.size());
        System.assertEquals('Completed', state.toolExecutions[0].status);
        System.assert(state.finalResponse.contains('Acme'));
        ProviderSecrets.openAiKeyOverride = null;
    }

    @IsTest
    static void runtimeRecordsFailedToolWhenDisabled() {
        ProviderSecrets.openAiKeyOverride = 'test-key';
        disabledInvocationCount = 0;
        Test.setMock(HttpCalloutMock.class, new DisabledToolMock());

        AgentConfig__c config = AgentConfigService.saveConfig(newConfigInput('openai', 'listObjects'));
        Id conversationId = OpenAfController.createConversation('Disabled Tool Test', config.Id);
        OpenAfModels.RunRequest request = new OpenAfModels.RunRequest();
        request.conversationId = conversationId;
        request.configId = config.Id;
        request.prompt = 'Try to query accounts.';
        request.triggerType = 'chat';

        Test.startTest();
        OpenAfController.submitPrompt(request);
        Test.stopTest();

        OpenAfModels.ConversationState state = OpenAfController.getConversationState(conversationId);
        System.assertEquals('Completed', state.runStatus);
        System.assertEquals(1, state.toolExecutions.size());
        System.assertEquals('Failed', state.toolExecutions[0].status);
        System.assert(state.toolExecutions[0].error.contains('disabled'));
        ProviderSecrets.openAiKeyOverride = null;
    }

    @IsTest
    static void scheduledTaskCreatesRunAndMarksTask() {
        ProviderSecrets.openAiKeyOverride = 'test-key';
        disabledInvocationCount = 1;
        Test.setMock(HttpCalloutMock.class, new DisabledToolMock());

        AgentConfig__c config = AgentConfigService.saveConfig(newConfigInput('openai', 'runSoql'));
        OpenAfModels.ScheduledTaskInput input = new OpenAfModels.ScheduledTaskInput();
        input.name = 'Nightly Summary';
        input.agentConfigId = config.Id;
        input.prompt = 'Summarize the org.';
        input.isRecurring = false;
        input.oneOffRunAt = System.now().addMinutes(1);
        input.status = 'Active';

        Test.startTest();
        ScheduledTask__c task = AgentScheduleService.saveScheduledTask(input);
        Test.stopTest();

        ScheduledTask__c refreshedTask = [
            SELECT Id, Status__c, LastRunStatus__c
            FROM ScheduledTask__c
            WHERE Id = :task.Id
            LIMIT 1
        ];
        List<Run__c> runs = [
            SELECT Id, ScheduledTask__c, Status__c
            FROM Run__c
            WHERE ScheduledTask__c = :task.Id
        ];

        System.assertEquals(1, runs.size());
        System.assertEquals('Completed', refreshedTask.Status__c);
        ProviderSecrets.openAiKeyOverride = null;
    }

    @IsTest
    static void cancelRunMarksQueuedRunCancelled() {
        AgentConfig__c config = AgentConfigService.saveConfig(newConfigInput('openai', 'runSoql'));

        Test.startTest();
        OpenAfModels.RunRequest request = new OpenAfModels.RunRequest();
        request.configId = config.Id;
        request.prompt = 'Start and then cancel.';
        request.triggerType = 'chat';

        OpenAfModels.RunResult queuedResult = OpenAfController.submitPrompt(request);
        OpenAfModels.RunResult cancelledResult = OpenAfController.cancelRun(queuedResult.runId);
        Test.stopTest();

        System.assertNotEquals(null, queuedResult.conversationId);
        System.assertEquals('Cancelled', cancelledResult.status);
        System.assertEquals('Cancelled by user.', cancelledResult.error);
    }

    @IsTest
    static void submitPromptCanContinueConversationAfterToolRun() {
        ProviderSecrets.openAiKeyOverride = 'test-key';
        repeatedConversationInvocationCount = 0;
        Test.setMock(HttpCalloutMock.class, new RepeatedConversationMock());

        AgentConfig__c config = AgentConfigService.saveConfig(newConfigInput('openai', 'runSoql'));
        Id conversationId = OpenAfController.createConversation('Repeated Conversation Test', config.Id);

        OpenAfModels.RunRequest firstRequest = new OpenAfModels.RunRequest();
        firstRequest.conversationId = conversationId;
        firstRequest.configId = config.Id;
        firstRequest.prompt = 'Find the first account.';
        firstRequest.triggerType = 'chat';

        OpenAfModels.RunRequest secondRequest = new OpenAfModels.RunRequest();
        secondRequest.conversationId = conversationId;
        secondRequest.configId = config.Id;
        secondRequest.prompt = 'What did you just find?';
        secondRequest.triggerType = 'chat';

        Test.startTest();
        OpenAfController.submitPrompt(firstRequest);
        OpenAfController.submitPrompt(secondRequest);
        Test.stopTest();

        OpenAfModels.ConversationState state = OpenAfController.getConversationState(conversationId);
        System.assertEquals('Completed', state.runStatus);
        System.assertEquals(null, state.error);
        System.assert(state.finalResponse.contains('Acme'));
        System.assertEquals(6, state.messages.size());
        ProviderSecrets.openAiKeyOverride = null;
    }

    private static OpenAfModels.ConfigInput newConfigInput(String provider, String enabledTools) {
        OpenAfModels.ConfigInput input = new OpenAfModels.ConfigInput();
        input.active = true;
        input.provider = provider;
        input.model = AgentConfigService.getDefaultModel(provider);
        input.systemPrompt = 'Test prompt';
        input.enabledTools = enabledTools;
        input.maxTurns = 3;
        return input;
    }
}
