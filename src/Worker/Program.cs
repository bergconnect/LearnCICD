using Shared;

// probe: CD env-gates ketenbewijs (Task 3).
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(HealthCheck.Build("Both")));

app.Run();

public partial class Program { }
