namespace SystemCare;

public sealed class AppChoice(InstalledApp app)
{
    public InstalledApp App { get; } = app;
    public bool IsSelected { get; set; }
}
