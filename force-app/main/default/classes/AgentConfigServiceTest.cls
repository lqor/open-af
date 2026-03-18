@IsTest
private class AgentConfigServiceTest {
    @IsTest
    static void createsDefaultConfigWhenMissing() {
        Test.startTest();
        AgentConfig__c config = AgentConfigService.getOrCreateDefaultConfig();
        Test.stopTest();

        System.assertNotEquals(null, config.Id);
        System.assertEquals(true, config.Active__c);
        System.assertEquals('anthropic', config.Provider__c);
        System.assertEquals(5, Integer.valueOf(config.MaxTurns__c.intValue()));
        System.assert(config.EnabledTools__c.contains('runSoql'));
    }

    @IsTest
    static void saveConfigActivatesLatestConfig() {
        AgentConfigService.getOrCreateDefaultConfig();

        OpenAfModels.ConfigInput input = new OpenAfModels.ConfigInput();
        input.active = true;
        input.provider = 'openai';
        input.model = 'gpt-4.1-mini';
        input.systemPrompt = 'test prompt';
        input.enabledTools = 'runSoql,listObjects';
        input.maxTurns = 3;

        Test.startTest();
        AgentConfig__c saved = AgentConfigService.saveConfig(input);
        Test.stopTest();

        List<AgentConfig__c> activeConfigs = [
            SELECT Id, Active__c, Provider__c, Model__c
            FROM AgentConfig__c
            WHERE Active__c = true
        ];
        System.assertEquals(1, activeConfigs.size());
        System.assertEquals(saved.Id, activeConfigs[0].Id);
        System.assertEquals('openai', activeConfigs[0].Provider__c);
        System.assertEquals('gpt-4.1-mini', activeConfigs[0].Model__c);
    }

    @IsTest
    static void providerFactorySelectsOpenAi() {
        OpenAfModels.ConfigInput input = new OpenAfModels.ConfigInput();
        input.active = true;
        input.provider = 'openai';
        input.model = 'gpt-4.1-mini';
        input.enabledTools = 'runSoql';
        input.maxTurns = 2;
        AgentConfig__c config = AgentConfigService.saveConfig(input);

        AgentProvider provider = AgentProviderFactory.getProvider(config);
        System.assertEquals('openai', provider.getName());
    }
}
