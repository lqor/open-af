public class AgentProviderFactory {
    @TestVisible private static AgentProvider providerOverride;

    public static AgentProvider getProvider(AgentConfig__c config) {
        if (Test.isRunningTest() && providerOverride != null) {
            return providerOverride;
        }

        String providerName = AgentConfigService.normalizeProvider(config == null ? null : config.Provider__c);
        if (providerName == 'openai') {
            return new OpenAiProvider();
        }
        return new AnthropicProvider();
    }
}
