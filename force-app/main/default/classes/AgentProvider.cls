public interface AgentProvider {
    String getName();
    OpenAfModels.ProviderResponse invoke(OpenAfModels.ProviderRequest request);
}
