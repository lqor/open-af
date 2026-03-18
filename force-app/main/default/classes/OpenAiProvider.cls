public with sharing class OpenAiProvider implements AgentProvider {
    public String getName() {
        return 'openai';
    }

    public OpenAfModels.ProviderResponse invoke(OpenAfModels.ProviderRequest request) {
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint('https://api.openai.com/v1/chat/completions');
        httpRequest.setMethod('POST');
        httpRequest.setHeader('Content-Type', 'application/json');
        httpRequest.setHeader('Authorization', 'Bearer ' + ProviderSecrets.getKey(getName()));
        httpRequest.setTimeout(120000);

        Map<String, Object> payload = new Map<String, Object>{
            'model' => String.isBlank(request.model) ? AgentConfigService.DEFAULT_OPENAI_MODEL : request.model,
            'messages' => toOpenAiMessages(request),
            'temperature' => 0.2
        };
        if (!request.tools.isEmpty()) {
            payload.put('tools', toOpenAiTools(request.tools));
            payload.put('tool_choice', 'auto');
        }

        httpRequest.setBody(JSON.serialize(payload));
        HttpResponse response = new Http().send(httpRequest);
        if (response.getStatusCode() >= 300) {
            throw new CalloutException('OpenAI call failed: ' + response.getStatusCode() + ' ' + response.getBody());
        }

        return parseResponse(response.getBody());
    }

    private static List<Object> toOpenAiMessages(OpenAfModels.ProviderRequest request) {
        List<Object> payload = new List<Object>();
        if (!String.isBlank(request.systemPrompt)) {
            payload.add(new Map<String, Object>{
                'role' => 'system',
                'content' => request.systemPrompt
            });
        }

        for (OpenAfModels.ProviderMessage message : request.messages) {
            if (message == null || String.isBlank(message.role)) {
                continue;
            }

            if (message.role == 'tool') {
                payload.add(new Map<String, Object>{
                    'role' => 'tool',
                    'content' => message.content,
                    'tool_call_id' => message.toolCallId,
                    'name' => message.toolName
                });
                continue;
            }

            if (message.role == 'assistant' && !message.toolCalls.isEmpty()) {
                List<Object> toolCalls = new List<Object>();
                for (OpenAfModels.ToolCall call : message.toolCalls) {
                    toolCalls.add(new Map<String, Object>{
                        'id' => call.id,
                        'type' => 'function',
                        'function' => new Map<String, Object>{
                            'name' => call.name,
                            'arguments' => call.inputJson
                        }
                    });
                }
                payload.add(new Map<String, Object>{
                    'role' => 'assistant',
                    'content' => String.isBlank(message.content) ? null : message.content,
                    'tool_calls' => toolCalls
                });
                continue;
            }

            payload.add(new Map<String, Object>{
                'role' => message.role,
                'content' => String.isBlank(message.content) ? '' : message.content
            });
        }
        return payload;
    }

    private static List<Object> toOpenAiTools(List<OpenAfModels.ProviderToolDefinition> tools) {
        List<Object> payload = new List<Object>();
        for (OpenAfModels.ProviderToolDefinition tool : tools) {
            payload.add(new Map<String, Object>{
                'type' => 'function',
                'function' => new Map<String, Object>{
                    'name' => tool.name,
                    'description' => tool.description,
                    'parameters' => tool.inputSchema
                }
            });
        }
        return payload;
    }

    private static OpenAfModels.ProviderResponse parseResponse(String body) {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(body);
        List<Object> choices = (List<Object>) raw.get('choices');
        if (choices == null || choices.isEmpty()) {
            throw new CalloutException('OpenAI response did not include choices.');
        }

        Map<String, Object> firstChoice = (Map<String, Object>) choices[0];
        Map<String, Object> message = (Map<String, Object>) firstChoice.get('message');
        OpenAfModels.ProviderResponse parsed = new OpenAfModels.ProviderResponse();
        parsed.rawResponse = body;
        parsed.assistantText = message == null ? null : (String) message.get('content');

        List<Object> rawToolCalls = message == null ? null : (List<Object>) message.get('tool_calls');
        if (rawToolCalls != null) {
            for (Object item : rawToolCalls) {
                Map<String, Object> toolCall = (Map<String, Object>) item;
                Map<String, Object> functionBlock = (Map<String, Object>) toolCall.get('function');
                OpenAfModels.ToolCall parsedCall = new OpenAfModels.ToolCall();
                parsedCall.id = (String) toolCall.get('id');
                parsedCall.name = functionBlock == null ? null : (String) functionBlock.get('name');
                parsedCall.inputJson = functionBlock == null ? '{}' : (String) functionBlock.get('arguments');
                parsed.toolCalls.add(parsedCall);
            }
        }
        return parsed;
    }
}
