using System.Text.Json.Serialization;

namespace DriveBatteryHealthViewer.Modern;

public sealed class CoreEnvelope
{
    [JsonPropertyName("schema")] public int Schema { get; set; }
    [JsonPropertyName("version")] public string Version { get; set; } = "1.0.6";
    [JsonPropertyName("generatedAt")] public DateTimeOffset GeneratedAt { get; set; }
    [JsonPropertyName("computer")] public string Computer { get; set; } = "";
    [JsonPropertyName("locale")] public string Locale { get; set; } = "zh-CN";
    [JsonPropertyName("historyDir")] public string HistoryDir { get; set; } = "";
    [JsonPropertyName("settings")] public CoreSettings Settings { get; set; } = new();
    [JsonPropertyName("disks")] public List<CoreDisk> Disks { get; set; } = [];
    [JsonPropertyName("batteries")] public List<CoreBattery> Batteries { get; set; } = [];
    [JsonPropertyName("history")] public List<CoreHistoryItem> History { get; set; } = [];
    [JsonPropertyName("report")] public string Report { get; set; } = "";
    [JsonPropertyName("error")] public string Error { get; set; } = "";
}

public sealed class CoreSettings
{
    [JsonPropertyName("language")] public string Language { get; set; } = "system";
    [JsonPropertyName("fontSize")] public int FontSize { get; set; } = 9;
    [JsonPropertyName("historyMode")] public string HistoryMode { get; set; } = "refresh";
    [JsonPropertyName("hideSerial")] public bool HideSerial { get; set; }
}

public sealed class CoreDisk
{
    [JsonPropertyName("number")] public int Number { get; set; }
    [JsonPropertyName("model")] public string Model { get; set; } = "";
    [JsonPropertyName("device")] public string Device { get; set; } = "";
    [JsonPropertyName("serial")] public string Serial { get; set; } = "";
    [JsonPropertyName("firmware")] public string Firmware { get; set; } = "";
    [JsonPropertyName("interface")] public string Interface { get; set; } = "";
    [JsonPropertyName("capacity")] public string Capacity { get; set; } = "";
    [JsonPropertyName("healthPercent")] public double? HealthPercent { get; set; }
    [JsonPropertyName("status")] public string Status { get; set; } = "";
    [JsonPropertyName("statusGood")] public bool StatusGood { get; set; }
    [JsonPropertyName("temperature")] public string Temperature { get; set; } = "";
    [JsonPropertyName("powerOnTime")] public string PowerOnTime { get; set; } = "";
    [JsonPropertyName("powerCycles")] public string PowerCycles { get; set; } = "";
    [JsonPropertyName("totalRead")] public string TotalRead { get; set; } = "";
    [JsonPropertyName("totalWritten")] public string TotalWritten { get; set; } = "";
    [JsonPropertyName("unsafeShutdowns")] public string UnsafeShutdowns { get; set; } = "";
    [JsonPropertyName("errorLogEntries")] public string ErrorLogEntries { get; set; } = "";
}

public sealed class CoreBattery
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("manufacturer")] public string Manufacturer { get; set; } = "";
    [JsonPropertyName("serial")] public string Serial { get; set; } = "";
    [JsonPropertyName("chemistry")] public string Chemistry { get; set; } = "";
    [JsonPropertyName("designCapacity")] public string DesignCapacity { get; set; } = "";
    [JsonPropertyName("fullCapacity")] public string FullCapacity { get; set; } = "";
    [JsonPropertyName("cycleCount")] public string CycleCount { get; set; } = "";
    [JsonPropertyName("healthPercent")] public double? HealthPercent { get; set; }
    [JsonPropertyName("status")] public string Status { get; set; } = "";
    [JsonPropertyName("statusGood")] public bool StatusGood { get; set; }
}

public sealed class CoreHistoryItem
{
    [JsonPropertyName("id")] public string ID { get; set; } = "";
    [JsonPropertyName("generatedAt")] public DateTimeOffset GeneratedAt { get; set; }
    [JsonPropertyName("computer")] public string Computer { get; set; } = "";
    [JsonPropertyName("source")] public string Source { get; set; } = "";
    [JsonPropertyName("report")] public string Report { get; set; } = "";
}
