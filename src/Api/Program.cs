// probe: prd-promote v6 proof round (no-op, cleanup via revert-PR)
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenApi();
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("Healthy"));
app.MapGet("/helloworld", () => Results.Ok("Hello, Both!"));

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.Run();

public partial class Program { }
