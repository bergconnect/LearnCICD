using Scalar.AspNetCore;

// LearnCICD Api service — routing probe (no behavior change).
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenApi();
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("Healthy"));
app.MapGet("/helloworld", () => Results.Ok("Hello, CI/CD!"));

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.Run();

public partial class Program { }
