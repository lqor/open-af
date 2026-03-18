public interface AgentTool {
    String getName();
    String getDescription();
    String getInputSchemaJson();
    String invoke(String inputJson, AgentToolContext context);
}
