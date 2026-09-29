using Shared;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(HealthCheck.Build("Both")));

app.Run();

public partial class Program { }
