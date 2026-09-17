using System.Net;
using System.Net.Sockets;
using System.Text;
using NetToPlc.Core.Models;
using NetToPlc.Core.Services;

Console.OutputEncoding = Encoding.UTF8;

var tests = new (string Name, Func<Task> Run)[]
{
    ("配置保存与读取", ConfigurationRoundTripAsync),
    ("TCP 双向转发", TcpBridgeRoundTripAsync),
    ("无效规则校验", RouteValidationRejectsInvalidPortsAsync),
};

var failures = new List<string>();

foreach (var test in tests)
{
    try
    {
        await test.Run();
        Console.WriteLine($"PASS  {test.Name}");
    }
    catch (Exception exception)
    {
        failures.Add($"{test.Name}: {exception.Message}");
        Console.WriteLine($"FAIL  {test.Name}");
        Console.WriteLine($"      {exception.Message}");
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine($"{failures.Count} 个测试失败。");
    return 1;
}

Console.WriteLine();
Console.WriteLine($"{tests.Length} 个测试全部通过。");
return 0;

static async Task ConfigurationRoundTripAsync()
{
    var directory = Path.Combine(Path.GetTempPath(), $"nettoplc-tests-{Guid.NewGuid():N}");
    var filePath = Path.Combine(directory, "config.json");

    try
    {
        var store = new ConfigurationStore(filePath);
        var expected = new AppConfiguration
        {
            StartRoutesOnLaunch = true,
            Routes =
            [
                new BridgeRoute
                {
                    Name = "round-trip",
                    ListenPort = 1502,
                    TargetPort = 1602,
                },
            ],
        };

        await store.SaveAsync(expected);
        var actual = await store.LoadAsync();

        Assert(actual.StartRoutesOnLaunch, "自动启动设置未保留。");
        Assert(actual.Routes.Count == 1, "规则数量不正确。");
        Assert(actual.Routes[0].Name == "round-trip", "规则名称未保留。");
        Assert(actual.Routes[0].ListenPort == 1502, "监听端口未保留。");
    }
    finally
    {
        if (Directory.Exists(directory))
        {
            Directory.Delete(directory, true);
        }
    }
}

static async Task TcpBridgeRoundTripAsync()
{
    using var echoServer = new TcpListener(IPAddress.Loopback, 0);
    echoServer.Start();
    var echoPort = ((IPEndPoint)echoServer.LocalEndpoint).Port;
    var bridgePort = GetFreePort();
    var payload = Encoding.UTF8.GetBytes("S7-bridge-smoke-test");

    var echoTask = Task.Run(async () =>
    {
        using var accepted = await echoServer.AcceptTcpClientAsync();
        var stream = accepted.GetStream();
        var buffer = new byte[payload.Length];
        await stream.ReadExactlyAsync(buffer);
        await stream.WriteAsync(buffer);
    });

    await using var engine = new BridgeEngine();
    var route = new BridgeRoute
    {
        Name = "smoke",
        ListenAddress = "127.0.0.1",
        ListenPort = bridgePort,
        TargetAddress = "127.0.0.1",
        TargetPort = echoPort,
        ConnectTimeoutMs = 3000,
    };

    await engine.StartRouteAsync(route);

    using var client = new TcpClient();
    await client.ConnectAsync(IPAddress.Loopback, bridgePort);
    var clientStream = client.GetStream();
    await clientStream.WriteAsync(payload);

    var response = new byte[payload.Length];
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    await clientStream.ReadExactlyAsync(response, timeout.Token);

    Assert(response.SequenceEqual(payload), "桥接返回的数据与发送数据不一致。");

    await engine.StopRouteAsync(route.Id);
    var snapshot = engine.GetSnapshot(route.Id);
    Assert(snapshot is null, "停止后的规则仍存在于运行表中。");

    await echoTask;
}

static Task RouteValidationRejectsInvalidPortsAsync()
{
    var route = new BridgeRoute
    {
        ListenPort = 0,
        TargetPort = 70000,
    };

    var errors = route.Validate();
    Assert(errors.Count >= 2, "无效端口未被拒绝。");
    return Task.CompletedTask;
}

static int GetFreePort()
{
    using var listener = new TcpListener(IPAddress.Loopback, 0);
    listener.Start();
    return ((IPEndPoint)listener.LocalEndpoint).Port;
}

static void Assert(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}
