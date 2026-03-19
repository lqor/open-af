@IsTest
private class RunApexToolTest {

    private static final String TOOL_NAME = 'runApex';
    private static AgentToolContext makeContext() {
        return new AgentToolContext(
            Test.getStandardPricebookId(), // dummy Id
            Test.getStandardPricebookId(),
            null,
            new AgentConfig__c()
        );
    }

    // ─── Query ────────────────────────────────────────────────────────────────

    @IsTest
    private static void query_returnsRecords() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        AgentTool tool = new RunApexTool();
        String input = JSON.serialize(new Map<String, Object>{
            'operation' => 'query',
            'soql' => 'SELECT Id,Name FROM Account LIMIT 5'
        });

        String result = tool.invoke(input, makeContext());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(true, parsed.get('success'), result);
        System.assertEquals('query', parsed.get('operation'));
        System.assertEquals(1, parsed.get('count'));
    }

    @IsTest
    private static void query_rejectsEmptySoql() {
        AgentTool tool = new RunApexTool();
        String result = tool.invoke(
            JSON.serialize(new Map<String, Object>{'operation' => 'query', 'soql' => ''}),
            makeContext()
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
    }

    @IsTest
    private static void query_enforcesLimit() {
        for (Integer i = 0; i < 5; i++) {
            insert new Account(Name = 'Query Limit Test ' + i);
        }
        AgentTool tool = new RunApexTool();
        String input = JSON.serialize(new Map<String, Object>{
            'operation' => 'query',
            'soql' => 'SELECT Id FROM Account WHERE Name LIKE \'Query Limit Test%\''
        });
        String result = tool.invoke(input, makeContext());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success'));
        System.assertEquals(5, parsed.get('count'));
    }

    @IsTest
    private static void query_invalidSoql_returnsError() {
        AgentTool tool = new RunApexTool();
        String result = tool.invoke(
            JSON.serialize(new Map<String, Object>{'operation' => 'query', 'soql' => 'SELECT FROM'}),
            makeContext()
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
    }

    // ─── Insert ───────────────────────────────────────────────────────────────

    @IsTest
    private static void insert_createsRecord() {
        AgentTool tool = new RunApexTool();
        String input = JSON.serialize(new Map<String, Object>{
            'operation' => 'insert',
            'soql' => 'INSERT INTO Account (Name,Industry) VALUES (\'Acme Corp\',\'Technology\')'
        });

        String result = tool.invoke(input, makeContext());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(true, parsed.get('success'), result);
        System.assertEquals('insert', parsed.get('operation'));
        System.assertEquals(1, parsed.get('successCount'));

        List<Object> results = (List<Object>) parsed.get('results');
        Map<String, Object> first = (Map<String, Object>) results[0];
        System.assertEquals(true, first.get('success'));
        // Verify record exists
        System.assertNotEquals(null, [SELECT Id FROM Account WHERE Id = :(Id) first.get('id')]);
    }

    @IsTest
    private static void insert_returnsErrorForUnknownObject() {
        AgentTool tool = new RunApexTool();
        String result = tool.invoke(
            JSON.serialize(new Map<String, Object>{
                'operation' => 'insert',
                'soql' => 'INSERT INTO NonExistentObject__c (Name) VALUES (\'Test\')'
            }),
            makeContext()
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
        String err = (String) parsed.get('error');
        System.assert(err.contains('Unknown object'), 'Expected "Unknown object" error, got: ' + err);
    }

    // ─── Update ───────────────────────────────────────────────────────────────

    @IsTest
    private static void update_modifiesRecords() {
        Account acct = new Account(Name = 'Update Test', Industry = 'Retail');
        insert acct;

        AgentTool tool = new RunApexTool();
        String input = JSON.serialize(new Map<String, Object>{
            'operation' => 'update',
            'soql' => 'UPDATE Account SET Industry=\'Technology\' WHERE Id=\'' + acct.Id + '\''
        });

        String result = tool.invoke(input, makeContext());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(true, parsed.get('success'), result);
        System.assertEquals(1, parsed.get('successCount'));

        Account updated = [SELECT Industry FROM Account WHERE Id = :acct.Id];
        System.assertEquals('Technology', updated.Industry);
    }

    @IsTest
    private static void update_zeroMatches_returnsZeroResults() {
        AgentTool tool = new RunApexTool();
        String result = tool.invoke(
            JSON.serialize(new Map<String, Object>{
                'operation' => 'update',
                'soql' => 'UPDATE Account SET Name=\'NoMatch\' WHERE Id=\'001000000000000XXX\''
            }),
            makeContext()
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(true, parsed.get('success')); // no error, just 0 matches
        System.assertEquals(0, parsed.get('successCount'));
    }

    // ─── Delete ───────────────────────────────────────────────────────────────

    @IsTest
    private static void delete_removesRecords() {
        Account acct = new Account(Name = 'Delete Test');
        insert acct;
        Id acctId = acct.Id;

        AgentTool tool = new RunApexTool();
        String input = JSON.serialize(new Map<String, Object>{
            'operation' => 'delete',
            'soql' => 'DELETE FROM Account WHERE Id=\'' + acctId + '\''
        });

        String result = tool.invoke(input, makeContext());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);

        System.assertEquals(true, parsed.get('success'), result);
        System.assertEquals(1, parsed.get('successCount'));
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Id = :acctId]);
    }

    // ─── Error handling ─────────────────────────────────────────────────────

    @IsTest
    private static void invalidOperation_returnsError() {
        AgentTool tool = new RunApexTool();
        String result = tool.invoke(
            JSON.serialize(new Map<String, Object>{
                'operation' => 'invalid',
                'soql' => 'SELECT Id FROM Account'
            }),
            makeContext()
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result);
        System.assertEquals(false, parsed.get('success'));
    }

    @IsTest
    private static void getName_returnsRunApex() {
        AgentTool tool = new RunApexTool();
        System.assertEquals('runApex', tool.getName());
    }

    @IsTest
    private static void getDescription_isNotBlank() {
        AgentTool tool = new RunApexTool();
        System.assert(String.isNotBlank(tool.getDescription()));
    }

    @IsTest
    private static void getInputSchemaJson_isValidSchema() {
        AgentTool tool = new RunApexTool();
        String schema = tool.getInputSchemaJson();
        // Should deserialize without error
        JSON.deserializeUntyped(schema);
        System.assert(schema.contains('query'));
        System.assert(schema.contains('insert'));
        System.assert(schema.contains('update'));
        System.assert(schema.contains('delete'));
    }
}
