public without sharing class AgentToolRegistry {
    public static Map<String, AgentTool> getAllTools() {
        Map<String, AgentTool> tools = new Map<String, AgentTool>();
        List<AgentTool> registrations = new List<AgentTool>{
            new RunSoqlTool(),
            new SearchRecordsTool(),
            new GetRecordTool(),
            new DescribeObjectTool(),
            new ListObjectsTool(),
            new CreateScheduledTaskTool(),
            new ListScheduledTasksTool(),
            new CancelScheduledTaskTool(),
            new ToolingQueryTool(),
            new ListFlowsTool(),
            new ListApexClassesTool(),
            new DescribePermissionsTool()
        };
        for (AgentTool tool : registrations) {
            tools.put(tool.getName(), tool);
        }
        return tools;
    }

    public static List<OpenAfModels.ProviderToolDefinition> describeTools(Set<String> enabledToolNames) {
        List<OpenAfModels.ProviderToolDefinition> definitions = new List<OpenAfModels.ProviderToolDefinition>();
        Map<String, AgentTool> allTools = getAllTools();
        List<String> names = new List<String>();
        names.addAll(allTools.keySet());
        names.sort();
        for (String name : names) {
            if (!enabledToolNames.contains(name)) {
                continue;
            }
            AgentTool tool = allTools.get(name);
            OpenAfModels.ProviderToolDefinition definition = new OpenAfModels.ProviderToolDefinition();
            definition.name = tool.getName();
            definition.description = tool.getDescription();
            definition.inputSchema = JSON.deserializeUntyped(tool.getInputSchemaJson());
            definitions.add(definition);
        }
        return definitions;
    }

    public static AgentTool requireTool(String name) {
        Map<String, AgentTool> tools = getAllTools();
        if (!tools.containsKey(name)) {
            throw new ToolException('Unsupported tool: ' + name);
        }
        return tools.get(name);
    }

    public class ToolException extends Exception {}

    private static Integer normalizeLimit(Object rawValue, Integer defaultValue, Integer maxValue) {
        Integer parsed = defaultValue;
        if (rawValue instanceof Integer) {
            parsed = (Integer) rawValue;
        } else if (rawValue instanceof Decimal) {
            parsed = Integer.valueOf(String.valueOf(((Decimal) rawValue).intValue()));
        } else if (rawValue != null) {
            parsed = Integer.valueOf(String.valueOf(rawValue));
        }
        parsed = parsed == null ? defaultValue : parsed;
        if (parsed <= 0) {
            parsed = defaultValue;
        }
        if (parsed > maxValue) {
            parsed = maxValue;
        }
        return parsed;
    }

    private static String firstAvailableField(Map<String, Schema.SObjectField> fields, List<String> candidates) {
        for (String candidate : candidates) {
            if (fields.containsKey(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private static String selfToolingQuery(String soql) {
        String sessionId = UserInfo.getSessionId();
        if (String.isBlank(sessionId)) {
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => 'Tooling API is unavailable in this async context because no session ID is available.'
            });
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(
            URL.getOrgDomainUrl().toExternalForm()
            + '/services/data/v62.0/tooling/query?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8')
        );
        request.setHeader('Authorization', 'Bearer ' + sessionId);
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() >= 300) {
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'statusCode' => response.getStatusCode(),
                'body' => response.getBody()
            });
        }
        return response.getBody();
    }

    public class RunSoqlTool implements AgentTool {
        public String getName() {
            return 'runSoql';
        }

        public String getDescription() {
            return 'Run a SOQL query against Salesforce data and return the records as JSON.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            String query = (String) input.get('query');
            List<SObject> records = Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'count' => records.size(),
                'records' => records
            });
        }
    }

    public class SearchRecordsTool implements AgentTool {
        public String getName() {
            return 'searchRecords';
        }

        public String getDescription() {
            return 'Search records in a specific object using a name-like field and return a small result set.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"objectApiName":{"type":"string"},"searchTerm":{"type":"string"},"limit":{"type":"integer"}},"required":["objectApiName","searchTerm"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            String objectApiName = (String) input.get('objectApiName');
            String searchTerm = (String) input.get('searchTerm');
            Integer limitSize = normalizeLimit(input.get('limit'), 10, 50);

            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            if (objectType == null) {
                return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => 'Unknown object: ' + objectApiName });
            }

            Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
            String nameField = firstAvailableField(fields, new List<String>{ 'Name', 'DeveloperName', 'MasterLabel', 'Subject', 'LastName' });
            if (nameField == null) {
                nameField = 'Id';
            }

            String query = 'SELECT Id,' + nameField + ' FROM ' + objectApiName;
            if (nameField != 'Id') {
                query += ' WHERE ' + nameField + ' LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'';
            }
            query += ' ORDER BY LastModifiedDate DESC LIMIT ' + limitSize;

            List<SObject> records = Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'query' => query,
                'count' => records.size(),
                'records' => records
            });
        }
    }

    public class GetRecordTool implements AgentTool {
        public String getName() {
            return 'getRecord';
        }

        public String getDescription() {
            return 'Fetch one Salesforce record by object API name and record Id.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"objectApiName":{"type":"string"},"recordId":{"type":"string"},"fields":{"type":"array","items":{"type":"string"}}},"required":["objectApiName","recordId"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            String objectApiName = (String) input.get('objectApiName');
            String recordId = (String) input.get('recordId');
            List<String> fieldsToSelect = new List<String>{ 'Id' };
            if (input.containsKey('fields') && input.get('fields') != null) {
                for (Object rawField : (List<Object>) input.get('fields')) {
                    String fieldName = String.valueOf(rawField);
                    if (!fieldsToSelect.contains(fieldName)) {
                        fieldsToSelect.add(fieldName);
                    }
                }
            } else {
                Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
                if (objectType != null) {
                    String nameField = firstAvailableField(objectType.getDescribe().fields.getMap(), new List<String>{ 'Name', 'DeveloperName', 'MasterLabel', 'Subject' });
                    if (nameField != null) {
                        fieldsToSelect.add(nameField);
                    }
                }
            }

            String query = 'SELECT ' + String.join(fieldsToSelect, ',') + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
            SObject record = Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'record' => record
            });
        }
    }

    public class DescribeObjectTool implements AgentTool {
        public String getName() {
            return 'describeObject';
        }

        public String getDescription() {
            return 'Describe an sObject including fields and basic capabilities.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"objectApiName":{"type":"string"}},"required":["objectApiName"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            String objectApiName = (String) input.get('objectApiName');
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            if (objectType == null) {
                return JSON.serialize(new Map<String, Object>{ 'success' => false, 'error' => 'Unknown object: ' + objectApiName });
            }

            Schema.DescribeSObjectResult describe = objectType.getDescribe();
            List<Object> fields = new List<Object>();
            for (String fieldName : describe.fields.getMap().keySet()) {
                Schema.DescribeFieldResult fieldDescribe = describe.fields.getMap().get(fieldName).getDescribe();
                fields.add(new Map<String, Object>{
                    'name' => fieldName,
                    'label' => fieldDescribe.getLabel(),
                    'type' => String.valueOf(fieldDescribe.getType()),
                    'createable' => fieldDescribe.isCreateable(),
                    'updateable' => fieldDescribe.isUpdateable(),
                    'nillable' => fieldDescribe.isNillable()
                });
            }
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'name' => describe.getName(),
                'label' => describe.getLabel(),
                'queryable' => describe.isQueryable(),
                'createable' => describe.isCreateable(),
                'updateable' => describe.isUpdateable(),
                'fields' => fields
            });
        }
    }

    public class ListObjectsTool implements AgentTool {
        public String getName() {
            return 'listObjects';
        }

        public String getDescription() {
            return 'List objects available in the org, optionally filtered by text.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"filter":{"type":"string"},"limit":{"type":"integer"}}}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = String.isBlank(inputJson)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            String filterText = ((String) input.get('filter')) == null ? null : ((String) input.get('filter')).toLowerCase();
            Integer limitSize = normalizeLimit(input.get('limit'), 50, 200);

            List<String> names = new List<String>();
            for (String apiName : Schema.getGlobalDescribe().keySet()) {
                if (String.isBlank(filterText) || apiName.toLowerCase().contains(filterText)) {
                    names.add(apiName);
                }
            }
            names.sort();
            if (names.size() > limitSize) {
                List<String> limited = new List<String>();
                for (Integer index = 0; index < limitSize; index++) {
                    limited.add(names[index]);
                }
                names = limited;
            }
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'count' => names.size(),
                'objects' => names
            });
        }
    }

    public class CreateScheduledTaskTool implements AgentTool {
        public String getName() {
            return 'createScheduledTask';
        }

        public String getDescription() {
            return 'Create or update a scheduled task that runs the same agent harness.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"name":{"type":"string"},"prompt":{"type":"string"},"agentConfigId":{"type":"string"},"isRecurring":{"type":"boolean"},"cronExpression":{"type":"string"},"oneOffRunAt":{"type":"string"}},"required":["name","prompt"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            OpenAfModels.ScheduledTaskInput input = new OpenAfModels.ScheduledTaskInput();
            input.name = (String) raw.get('name');
            input.prompt = (String) raw.get('prompt');
            input.agentConfigId = (Id) raw.get('agentConfigId');
            input.isRecurring = (Boolean) raw.get('isRecurring');
            input.cronExpression = (String) raw.get('cronExpression');
            input.status = 'Active';
            if (raw.get('oneOffRunAt') != null) {
                input.oneOffRunAt = Datetime.valueOfGmt(String.valueOf(raw.get('oneOffRunAt')).replace('T', ' ').replace('Z', ''));
            }
            ScheduledTask__c task = AgentScheduleService.saveScheduledTask(input);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'taskId' => task.Id,
                'jobId' => task.JobId__c
            });
        }
    }

    public class ListScheduledTasksTool implements AgentTool {
        public String getName() {
            return 'listScheduledTasks';
        }

        public String getDescription() {
            return 'List saved scheduled tasks and their statuses.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"status":{"type":"string"}}}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = String.isBlank(inputJson)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            String desiredStatus = (String) input.get('status');

            String query = 'SELECT Id, Name, AgentConfig__c, Prompt__c, IsRecurring__c, CronExpression__c, OneOffRunAt__c, Status__c, JobId__c, LastRunAt__c, LastRunStatus__c, CreatedDate FROM ScheduledTask__c';
            if (!String.isBlank(desiredStatus)) {
                query += ' WHERE Status__c = :desiredStatus';
            }
            query += ' ORDER BY CreatedDate DESC LIMIT 50';

            List<SObject> tasks = Database.query(query);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'tasks' => tasks
            });
        }
    }

    public class CancelScheduledTaskTool implements AgentTool {
        public String getName() {
            return 'cancelScheduledTask';
        }

        public String getDescription() {
            return 'Abort a scheduled task and mark it paused.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"taskId":{"type":"string"}},"required":["taskId"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            Id taskId = (Id) input.get('taskId');
            AgentScheduleService.cancelScheduledTask(taskId);
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'taskId' => taskId
            });
        }
    }

    public class ToolingQueryTool implements AgentTool {
        public String getName() {
            return 'toolingQuery';
        }

        public String getDescription() {
            return 'Run a Tooling API SOQL query against setup metadata via the org REST API.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            return selfToolingQuery((String) input.get('query'));
        }
    }

    public class ListFlowsTool implements AgentTool {
        public String getName() {
            return 'listFlows';
        }

        public String getDescription() {
            return 'List Flow definitions available in the org.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"limit":{"type":"integer"}}}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = String.isBlank(inputJson)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            Integer limitSize = normalizeLimit(input.get('limit'), 25, 100);
            return selfToolingQuery('SELECT Id, DeveloperName, MasterLabel, ActiveVersionId, LatestVersionId FROM FlowDefinitionView LIMIT ' + limitSize);
        }
    }

    public class ListApexClassesTool implements AgentTool {
        public String getName() {
            return 'listApexClasses';
        }

        public String getDescription() {
            return 'List Apex classes from the org using Tooling API.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"limit":{"type":"integer"}}}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = String.isBlank(inputJson)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            Integer limitSize = normalizeLimit(input.get('limit'), 25, 100);
            return selfToolingQuery('SELECT Id, Name, ApiVersion, Status FROM ApexClass LIMIT ' + limitSize);
        }
    }

    public class DescribePermissionsTool implements AgentTool {
        public String getName() {
            return 'describePermissions';
        }

        public String getDescription() {
            return 'List permission sets and profile names for quick org-permission inspection.';
        }

        public String getInputSchemaJson() {
            return '{"type":"object","properties":{"limit":{"type":"integer"}}}';
        }

        public String invoke(String inputJson, AgentToolContext context) {
            Map<String, Object> input = String.isBlank(inputJson)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(inputJson);
            Integer limitSize = normalizeLimit(input.get('limit'), 25, 100);

            List<PermissionSet> permissionSets = [
                SELECT Id, Name, Label, Profile.Name, IsOwnedByProfile
                FROM PermissionSet
                ORDER BY Label
                LIMIT :limitSize
            ];
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'permissionSets' => permissionSets
            });
        }
    }
}
