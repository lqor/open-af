public without sharing class RunApexTool implements AgentTool {

    private static final Integer MAX_QUERY_ROWS = 1000;
    private static final Integer MAX_DML_RECORDS = 200;

    public String getName() {
        return 'runApex';
    }

    public String getDescription() {
        return 'Execute SOQL queries and DML operations (INSERT, UPDATE, DELETE) against Salesforce. Returns records as JSON.';
    }

    public String getInputSchemaJson() {
        return '{"type":"object","properties":{"operation":{"type":"string","enum":["query","insert","update","delete"]},"soql":{"type":"string","description":"SOQL statement. Examples: SELECT Id,Name FROM Account LIMIT 5 | INSERT INTO Account (Name) VALUES (\'Acme\') | UPDATE Account SET Name=\'New Name\' WHERE Id=\'recordId\' | DELETE FROM Account WHERE Id=\'recordId\'"}}}';
    }

    public String invoke(String inputJson, AgentToolContext context) {
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(inputJson);
        String operation = (String) input.get('operation');
        String soql = ((String) input.get('soql')).trim();

        if (String.isBlank(soql)) {
            return errorResult('SOQL statement is required.');
        }

        try {
            if (operation == 'query') {
                return runQuery(soql);
            } else if (operation == 'insert') {
                return runInsert(soql);
            } else if (operation == 'update') {
                return runUpdate(soql);
            } else if (operation == 'delete') {
                return runDelete(soql);
            } else {
                return errorResult('Unsupported operation: ' + operation + '. Use query, insert, update, or delete.');
            }
        } catch (Exception e) {
            return errorResult(e.getMessage() + ' [line: ' + e.getLineNumber() + ']');
        }
    }

    // ─── Query ────────────────────────────────────────────────────────────────

    private String runQuery(String soql) {
        String safeSoql = appendLimit(soql, MAX_QUERY_ROWS);
        List<SObject> records = Database.query(safeSoql);
        return JSON.serialize(new Map<String, Object>{
            'success' => true,
            'operation' => 'query',
            'count' => records.size(),
            'records' => records
        });
    }

    // ─── Insert ───────────────────────────────────────────────────────────────

    private String runInsert(String soql) {
        // INSERT INTO Account (Name,Industry) VALUES ('Acme','Tech')
        Pattern p = Pattern.compile(
            '(?i)\\s*INSERT\\s+INTO\\s+(\\w+)\\s*\\(([^)]+)\\)\\s+VALUES\\s*\\(([^)]+)\\)' +
            // Note: inside character class, ) does NOT need escaping
            ''
        );
        Matcher m = p.matcher(soql);
        if (!m.matches()) {
            return errorResult('Invalid INSERT syntax. Expected: INSERT INTO Account (Field1,Field2) VALUES (\'Value1\',\'Value2\')');
        }

        String objectName = m.group(1);
        List<String> fieldNames = splitIdentifiers(m.group(2));
        List<String> rawValues = splitIdentifiers(m.group(3));

        if (fieldNames.size() != rawValues.size()) {
            return errorResult('Field count (' + fieldNames.size() + ') != value count (' + rawValues.size() + ').');
        }

        SObjectType token = Schema.getGlobalDescribe().get(objectName);
        if (token == null) {
            return errorResult('Unknown object: ' + objectName);
        }

        Map<String, Schema.SObjectField> fieldMap = token.getDescribe().fields.getMap();
        SObject record = token.newSObject();
        for (Integer i = 0; i < fieldNames.size(); i++) {
            String fld = fieldNames[i].trim();
            String rawVal = rawValues[i].trim();
            record.put(fld, parseLiteral(rawVal, fieldMap.get(fld)));
        }
        insert record;

        return JSON.serialize(new Map<String, Object>{
            'success' => true,
            'operation' => 'insert',
            'id' => record.Id,
            'successCount' => 1,
            'count' => 1,
            'results' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'success' => true, 'id' => record.Id }
            }
        });
    }

    // ─── Update ───────────────────────────────────────────────────────────────

    private String runUpdate(String soql) {
        // UPDATE Account SET Name='Acme Corp',Industry='Tech' WHERE Id='001...'
        // (?i) at start enables case-insensitive matching
        Pattern p = Pattern.compile('(?i)\\s*UPDATE\\s+(\\w+)\\s+SET\\s+(.+)\\s+WHERE\\s+(.+)');
        Matcher m = p.matcher(soql);
        if (!m.matches()) {
            return errorResult('Invalid UPDATE syntax. Expected: UPDATE Account SET Field1=\'Value1\' WHERE Id=\'recordId\'');
        }

        String objectName = m.group(1);
        String setClause = m.group(2);
        String whereClause = m.group(3);

        SObjectType token = Schema.getGlobalDescribe().get(objectName);
        if (token == null) {
            return errorResult('Unknown object: ' + objectName);
        }

        Map<String, Object> fieldValues = parseSetClause(setClause, token.getDescribe().fields.getMap());

        String whereQuery = appendLimit(
            'SELECT Id FROM ' + objectName + ' WHERE ' + whereClause,
            MAX_DML_RECORDS
        );
        List<SObject> targets = Database.query(whereQuery);

        if (targets.isEmpty()) {
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'operation' => 'update',
                'totalCount' => 0,
                'successCount' => 0
            });
        }

        for (SObject t : targets) {
            for (String fld : fieldValues.keySet()) {
                t.put(fld, fieldValues.get(fld));
            }
        }
        update targets;

        return JSON.serialize(new Map<String, Object>{
            'success' => true,
            'operation' => 'update',
            'totalCount' => targets.size(),
            'successCount' => targets.size(),
            'ids' => collectIds(targets)
        });
    }

    // ─── Delete ───────────────────────────────────────────────────────────────

    private String runDelete(String soql) {
        Pattern p = Pattern.compile('(?i)\\s*DELETE\\s+FROM\\s+(\\w+)\\s+WHERE\\s+(.+)');
        Matcher m = p.matcher(soql);
        if (!m.matches()) {
            return errorResult('Invalid DELETE syntax. Expected: DELETE FROM Account WHERE Id=\'recordId\'');
        }

        String objectName = m.group(1);
        String whereClause = m.group(2);

        SObjectType token = Schema.getGlobalDescribe().get(objectName);
        if (token == null) {
            return errorResult('Unknown object: ' + objectName);
        }

        String whereQuery = appendLimit(
            'SELECT Id FROM ' + objectName + ' WHERE ' + whereClause,
            MAX_DML_RECORDS
        );
        List<SObject> targets = Database.query(whereQuery);

        if (targets.isEmpty()) {
            return JSON.serialize(new Map<String, Object>{
                'success' => true,
                'operation' => 'delete',
                'totalCount' => 0,
                'successCount' => 0
            });
        }

        delete targets;
        return JSON.serialize(new Map<String, Object>{
            'success' => true,
            'operation' => 'delete',
            'totalCount' => targets.size(),
            'successCount' => targets.size(),
            'deletedIds' => collectIds(targets)
        });
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private String appendLimit(String soql, Integer maxRows) {
        if (Pattern.compile('(?i)\\sLIMIT\\s+\\d+$').matcher(soql).find()) {
            return soql;
        }
        return soql + ' LIMIT ' + maxRows;
    }

    private List<String> splitIdentifiers(String input) {
        List<String> result = new List<String>();
        String current = '';
        Boolean inSingleQuote = false;
        Boolean escaped = false;
        for (Integer i = 0; i < input.length(); i++) {
            String ch = input.substring(i, i + 1);
            if (!escaped && ch == '\'') {
                inSingleQuote = !inSingleQuote;
                current += ch;
            } else if (!escaped && ch == '\\') {
                escaped = true;
                current += ch;
            } else if (!inSingleQuote && ch == ',') {
                result.add(current);
                current = '';
                escaped = false;
            } else {
                current += ch;
                escaped = false;
            }
        }
        if (String.isNotBlank(current)) {
            result.add(current);
        }
        return result;
    }

    private Object parseLiteral(String raw, Schema.SObjectField fld) {
        raw = raw.trim();
        if (raw == 'NULL') return null;

        // Strip surrounding single quotes
        if (raw.startsWith('\'') && raw.endsWith('\'')) {
            String unquoted = raw.substring(1, raw.length() - 1);
            return unquoted.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\');
        }

        if (raw.equalsIgnoreCase('TRUE')) return true;
        if (raw.equalsIgnoreCase('FALSE')) return false;

        if (raw.contains('.')) {
            return Decimal.valueOf(raw);
        }
        return Integer.valueOf(raw);
    }

    private Map<String, Object> parseSetClause(String setClause, Map<String, Schema.SObjectField> fieldMap) {
        Map<String, Object> fieldValues = new Map<String, Object>();
        List<String> pairs = splitIdentifiers(setClause);
        for (String pair : pairs) {
            Integer eqIdx = pair.indexOf('=');
            if (eqIdx < 0) continue;
            String fld = pair.substring(0, eqIdx).trim();
            String rawVal = pair.substring(eqIdx + 1).trim();
            fieldValues.put(fld, parseLiteral(rawVal, fieldMap.get(fld)));
        }
        return fieldValues;
    }

    private List<Id> collectIds(List<SObject> records) {
        List<Id> ids = new List<Id>();
        for (SObject r : records) {
            ids.add(r.Id);
        }
        return ids;
    }

    private String errorResult(String message) {
        return JSON.serialize(new Map<String, Object>{
            'success' => false,
            'error' => message
        });
    }
}
