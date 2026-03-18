@IsTest
private class ProviderAdapterTest {
    private class ProviderMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            if (request.getEndpoint().contains('anthropic.com')) {
                response.setBody('{"id":"msg_1","content":[{"type":"text","text":"I checked the org."},{"type":"tool_use","id":"toolu_1","name":"listObjects","input":{"filter":"Acc"}}]}');
            } else {
                response.setBody('{"choices":[{"message":{"content":"I found data.","tool_calls":[{"id":"call_1","type":"function","function":{"name":"runSoql","arguments":"{\\"query\\":\\"SELECT Id FROM Account LIMIT 1\\"}"}}]}}]}');
            }
            return response;
        }
    }

    @IsTest
    static void anthropicProviderNormalizesTextAndToolUse() {
        ProviderSecrets.anthropicKeyOverride = 'test-key';
        Test.setMock(HttpCalloutMock.class, new ProviderMock());

        OpenAfModels.ProviderRequest request = new OpenAfModels.ProviderRequest();
        request.model = AgentConfigService.DEFAULT_ANTHROPIC_MODEL;
        request.systemPrompt = 'Test';
        OpenAfModels.ProviderMessage message = new OpenAfModels.ProviderMessage();
        message.role = 'user';
        message.content = 'List objects';
        request.messages.add(message);

        Test.startTest();
        OpenAfModels.ProviderResponse response = new AnthropicProvider().invoke(request);
        Test.stopTest();

        System.assertEquals('I checked the org.', response.assistantText);
        System.assertEquals(1, response.toolCalls.size());
        System.assertEquals('listObjects', response.toolCalls[0].name);
        System.assert(response.toolCalls[0].inputJson.contains('Acc'));
        ProviderSecrets.anthropicKeyOverride = null;
    }

    @IsTest
    static void openAiProviderNormalizesTextAndToolCalls() {
        ProviderSecrets.openAiKeyOverride = 'test-key';
        Test.setMock(HttpCalloutMock.class, new ProviderMock());

        OpenAfModels.ProviderRequest request = new OpenAfModels.ProviderRequest();
        request.model = AgentConfigService.DEFAULT_OPENAI_MODEL;
        request.systemPrompt = 'Test';
        OpenAfModels.ProviderMessage message = new OpenAfModels.ProviderMessage();
        message.role = 'user';
        message.content = 'Run a query';
        request.messages.add(message);

        Test.startTest();
        OpenAfModels.ProviderResponse response = new OpenAiProvider().invoke(request);
        Test.stopTest();

        System.assertEquals('I found data.', response.assistantText);
        System.assertEquals(1, response.toolCalls.size());
        System.assertEquals('runSoql', response.toolCalls[0].name);
        System.assert(response.toolCalls[0].inputJson.contains('SELECT Id FROM Account LIMIT 1'));
        ProviderSecrets.openAiKeyOverride = null;
    }
}
