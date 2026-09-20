using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Api.Tests;

public class HelloWorldEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public HelloWorldEndpointTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetHelloWorld_ReturnsOkWithHelloWorldBody()
    {
        var response = await _client.GetAsync("/helloworld", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken);
        Assert.Contains("Hello, CI/CD!", body);
    }
}
