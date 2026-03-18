public with sharing class AnthropicProvider implements AgentProvider {
    public String getName() {
        return 'anthropic';
    }

    public OpenAfModels.ProviderResponse invoke(OpenAfModels.ProviderRequest request) {
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint('https://api.anthropic.com/v1/messages');
        httpRequest.setMethod('POST');
        httpRequest.setHeader('Content-Type', 'application/json');
        httpRequest.setHeader('x-api-key', ProviderSecrets.getKey(getName()));
        httpRequest.setHeader('anthropic-version', '2023-06-01');
        httpRequest.setTimeout(120000);

        Map<String, Object> payload = new Map<String, Object>{
            'model' => String.isBlank(request.model) ? AgentConfigService.DEFAULT_ANTHROPIC_MODEL : request.model,
            'max_tokens' => request.maxTokens == null ? 1024 : request.maxTokens,
            'messages' => toAnthropicMessages(request.messages)
        };
        if (!String.isBlank(request.systemPrompt)) {
            payload.put('system', request.systemPrompt);
        }
        if (!request.tools.isEmpty()) {
            payload.put('tools', toAnthropicTools(request.tools));
        }

        httpRequest.setBody(JSON.serialize(payload));
        HttpResponse response = new Http().send(httpRequest);
        if (response.getStatusCode() >= 300) {
            throw new CalloutException('Anthropic call failed: ' + response.getStatusCode() + ' ' + response.getBody());
        }

        return parseResponse(response.getBody());
    }

    private static List<Object> toAnthropicTools(List<OpenAfModels.ProviderToolDefinition> tools) {
        List<Object> payload = new List<Object>();
        for (OpenAfModels.ProviderToolDefinition tool : tools) {
            payload.add(new Map<String, Object>{
                'name' => tool.name,
                'description' => tool.description,
                'input_schema' => tool.inputSchema
            });
        }
        return payload;
    }

    private static List<Object> toAnthropicMessages(List<OpenAfModels.ProviderMessage> messages) {
        List<Object> payload = new List<Object>();
        for (OpenAfModels.ProviderMessage message : messages) {
            if (message == null || String.isBlank(message.role)) {
                continue;
            }

            if (message.role == 'tool') {
                payload.add(new Map<String, Object>{
                    'role' => 'user',
                    'content' => new List<Object>{
                        new Map<String, Object>{
                            'type' => 'tool_result',
                            'tool_use_id' => message.toolCallId,
                            'content' => message.content
                        }
                    }
                });
                continue;
            }

            if (message.role == 'assistant' && !message.toolCalls.isEmpty()) {
                List<Object> blocks = new List<Object>();
                if (!String.isBlank(message.content)) {
                    blocks.add(new Map<String, Object>{
                        'type' => 'text',
                        'text' => message.content
                    });
                }
                for (OpenAfModels.ToolCall call : message.toolCalls) {
                    blocks.add(new Map<String, Object>{
                        'type' => 'tool_use',
                        'id' => call.id,
                        'name' => call.name,
                        'input' => JSON.deserializeUntyped(call.inputJson)
                    });
                }
                payload.add(new Map<String, Object>{
                    'role' => 'assistant',
                    'content' => blocks
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

    private static OpenAfModels.ProviderResponse parseResponse(String body) {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(body);
        List<Object> contentBlocks = (List<Object>) raw.get('content');
        List<String> texts = new List<String>();
        OpenAfModels.ProviderResponse parsed = new OpenAfModels.ProviderResponse();
        parsed.rawResponse = body;

        if (contentBlocks != null) {
            for (Object item : contentBlocks) {
                Map<String, Object> block = (Map<String, Object>) item;
                String blockType = (String) block.get('type');
                if (blockType == 'text') {
                    texts.add((String) block.get('text'));
                } else if (blockType == 'tool_use') {
                    OpenAfModels.ToolCall call = new OpenAfModels.ToolCall();
                    call.id = (String) block.get('id');
                    call.name = (String) block.get('name');
                    call.inputJson = JSON.serialize(block.get('input'));
                    parsed.toolCalls.add(call);
                }
            }
        }

        parsed.assistantText = String.join(texts, '\n\n');
        return parsed;
    }
}
