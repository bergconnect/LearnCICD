namespace Shared;

public static class HealthCheck
{
    public static string Build(string service) => $"Healthy {service}!";
}
