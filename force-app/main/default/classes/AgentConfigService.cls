public without sharing class AgentConfigService {
    public static final String DEFAULT_PROVIDER = 'anthropic';
    public static final String DEFAULT_ANTHROPIC_MODEL = 'claude-3-5-sonnet-20241022';
    public static final String DEFAULT_OPENAI_MODEL = 'gpt-4.1-mini';
    public static final String DEFAULT_SYSTEM_PROMPT = 'You are Open AF, a concise Salesforce sandbox agent. Use tools when needed, explain what you found, and stay grounded in org data.';

    public static AgentConfig__c getConfig(Id configId) {
        if (configId == null) {
            return getOrCreateDefaultConfig();
        }
        List<AgentConfig__c> configs = [
            SELECT Id, Name, Active__c, Provider__c, Model__c, SystemPrompt__c, EnabledTools__c, MaxTurns__c
            FROM AgentConfig__c
            WHERE Id = :configId
            LIMIT 1
        ];
        return configs.isEmpty() ? getOrCreateDefaultConfig() : configs[0];
    }

    public static AgentConfig__c getOrCreateDefaultConfig() {
        List<AgentConfig__c> configs = [
            SELECT Id, Name, Active__c, Provider__c, Model__c, SystemPrompt__c, EnabledTools__c, MaxTurns__c
            FROM AgentConfig__c
            WHERE Active__c = true
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (!configs.isEmpty()) {
            return configs[0];
        }

        AgentConfig__c config = new AgentConfig__c(
            Active__c = true,
            Provider__c = DEFAULT_PROVIDER,
            Model__c = DEFAULT_ANTHROPIC_MODEL,
            SystemPrompt__c = DEFAULT_SYSTEM_PROMPT,
            EnabledTools__c = String.join(getDefaultToolNames(), ','),
            MaxTurns__c = 5
        );
        insert config;
        return config;
    }

    public static AgentConfig__c saveConfig(OpenAfModels.ConfigInput input) {
        AgentConfig__c config = input != null && input.id != null
            ? [
                SELECT Id, Active__c, Provider__c, Model__c, SystemPrompt__c, EnabledTools__c, MaxTurns__c
                FROM AgentConfig__c
                WHERE Id = :input.id
                LIMIT 1
            ]
            : new AgentConfig__c();

        config.Active__c = input == null || input.active == null ? true : input.active;
        config.Provider__c = normalizeProvider(input == null ? null : input.provider);
        config.Model__c = String.isBlank(input == null ? null : input.model)
            ? getDefaultModel(config.Provider__c)
            : input.model.trim();
        config.SystemPrompt__c = String.isBlank(input == null ? null : input.systemPrompt)
            ? DEFAULT_SYSTEM_PROMPT
            : input.systemPrompt.trim();
        config.EnabledTools__c = normalizeEnabledTools(input == null ? null : input.enabledTools);
        config.MaxTurns__c = input == null || input.maxTurns == null || input.maxTurns <= 0 ? 5 : input.maxTurns;

        if (config.Id == null) {
            insert config;
        } else {
            update config;
        }

        if (config.Active__c) {
            deactivateOthers(config.Id);
        }
        return getConfig(config.Id);
    }

    public static List<OpenAfModels.ConfigView> getConfigViews() {
        List<OpenAfModels.ConfigView> views = new List<OpenAfModels.ConfigView>();
        for (AgentConfig__c config : [
            SELECT Id, Name, Active__c, Provider__c, Model__c, SystemPrompt__c, EnabledTools__c, MaxTurns__c
            FROM AgentConfig__c
            ORDER BY Active__c DESC, CreatedDate ASC
        ]) {
            views.add(toView(config));
        }

        if (views.isEmpty()) {
            AgentConfig__c defaultConfig = getOrCreateDefaultConfig();
            views.add(toView(defaultConfig));
        }
        return views;
    }

    public static OpenAfModels.ConfigView toView(AgentConfig__c config) {
        OpenAfModels.ConfigView view = new OpenAfModels.ConfigView();
        view.id = config.Id;
        view.active = config.Active__c;
        view.provider = config.Provider__c;
        view.model = config.Model__c;
        view.systemPrompt = config.SystemPrompt__c;
        view.enabledTools = config.EnabledTools__c;
        view.maxTurns = config.MaxTurns__c;
        view.label = (config.Active__c ? 'Active' : 'Saved') + ' - ' + config.Provider__c + ' / ' + config.Model__c;
        return view;
    }

    public static Set<String> enabledToolSet(AgentConfig__c config) {
        Set<String> names = new Set<String>();
        String raw = config == null ? null : config.EnabledTools__c;
        if (String.isBlank(raw)) {
            names.addAll(getDefaultToolNames());
            return names;
        }

        for (String token : raw.split('[,\\n\\r]+')) {
            String cleaned = token == null ? null : token.trim();
            if (!String.isBlank(cleaned)) {
                names.add(cleaned);
            }
        }
        if (names.isEmpty()) {
            names.addAll(getDefaultToolNames());
        }
        return names;
    }

    public static List<String> getDefaultToolNames() {
        return new List<String>{
            'runSoql',
            'searchRecords',
            'getRecord',
            'describeObject',
            'listObjects',
            'toolingQuery',
            'listFlows',
            'listApexClasses',
            'describePermissions'
        };
    }

    public static String normalizeProvider(String provider) {
        String normalized = String.isBlank(provider) ? DEFAULT_PROVIDER : provider.trim().toLowerCase();
        return normalized == 'openai' ? 'openai' : 'anthropic';
    }

    public static String getDefaultModel(String provider) {
        return normalizeProvider(provider) == 'openai' ? DEFAULT_OPENAI_MODEL : DEFAULT_ANTHROPIC_MODEL;
    }

    private static void deactivateOthers(Id activeId) {
        List<AgentConfig__c> others = [
            SELECT Id, Active__c
            FROM AgentConfig__c
            WHERE Active__c = true AND Id != :activeId
        ];
        for (AgentConfig__c row : others) {
            row.Active__c = false;
        }
        if (!others.isEmpty()) {
            update others;
        }
    }

    private static String normalizeEnabledTools(String enabledTools) {
        Set<String> cleaned = new Set<String>();
        if (String.isBlank(enabledTools)) {
            cleaned.addAll(getDefaultToolNames());
        } else {
            for (String token : enabledTools.split('[,\\n\\r]+')) {
                String value = token == null ? null : token.trim();
                if (!String.isBlank(value)) {
                    cleaned.add(value);
                }
            }
        }
        if (cleaned.isEmpty()) {
            cleaned.addAll(getDefaultToolNames());
        }
        List<String> sortedNames = new List<String>();
        sortedNames.addAll(cleaned);
        sortedNames.sort();
        return String.join(sortedNames, ',');
    }
}
