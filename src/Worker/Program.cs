// LearnCICD Worker service — routing probe (no behavior change).
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("Healthy, Roundtrip!"));

app.Run();

public partial class Program { }
