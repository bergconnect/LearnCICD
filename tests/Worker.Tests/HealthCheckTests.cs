using Shared;

namespace Worker.Tests;

public class HealthCheckTests
{
    [Fact]
    public void Build_ReturnsHealthyMessage()
    {
        Assert.Equal("Healthy, Both!", HealthCheck.Build("Both"));
    }
}
