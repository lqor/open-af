public class ProviderSecrets {
    public class ConfigurationException extends Exception {}

    public static final String ANTHROPIC_API_KEY = 'REPLACE_ME_ANTHROPIC_KEY';
    public static final String OPENAI_API_KEY = 'REPLACE_ME_OPENAI_KEY';
    @TestVisible private static String anthropicKeyOverride;
    @TestVisible private static String openAiKeyOverride;

    public static String getKey(String providerName) {
        String normalized = String.isBlank(providerName) ? 'anthropic' : providerName.trim().toLowerCase();
        if (normalized == 'anthropic') {
            String keyValue = Test.isRunningTest() && !String.isBlank(anthropicKeyOverride) ? anthropicKeyOverride : ANTHROPIC_API_KEY;
            validateKey(keyValue, 'Anthropic');
            return keyValue;
        }
        if (normalized == 'openai') {
            String keyValue = Test.isRunningTest() && !String.isBlank(openAiKeyOverride) ? openAiKeyOverride : OPENAI_API_KEY;
            validateKey(keyValue, 'OpenAI');
            return keyValue;
        }
        throw new ConfigurationException('Unsupported provider: ' + providerName);
    }

    private static void validateKey(String value, String label) {
        if (String.isBlank(value) || value.startsWith('REPLACE_ME')) {
            throw new ConfigurationException(label + ' API key is not configured in ProviderSecrets. Keep secrets in a local .env file and inject them into org configuration outside git.');
        }
    }
}
