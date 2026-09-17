# NetToPLC Bridge

一个面向 PLC / PLCSIM 联调场景的 Windows 网络桥接工具。它既支持普通 TCP 透传，也支持通过西门子 S7Online 把 EET Pro 等 S7 客户端连接到 PLCSIM 实例。

## 功能

- 多条映射规则并行运行，每条规则使用独立监听端口。
- EET Pro/Snap7 客户端通过 ISO-on-TCP 接入，后端使用 PLCSIM S7Online。
- 本机监听地址和目标地址可独立配置，支持 IPv4、IPv6 和主机名。
- 实时展示规则状态、活跃连接数、累计连接数和双向流量。
- 规则与运行状态分离，编辑后保存即可应用；运行中的规则会自动重启。
- 配置自动持久化到 `%LOCALAPPDATA%\NetToPlcBridge\config.json`。
- 提供运行日志，方便排查端口占用、目标不可达和连接超时。
- 支持 Windows 启动后由程序自动启动全部已启用规则。

## 运行

环境要求：Windows 10/11，已安装 .NET 8 Desktop Runtime 或 .NET 8 SDK。

```powershell
dotnet run --project .\src\NetToPlc.App\NetToPlc.App.csproj -c Release
```

也可以在构建后直接运行：

```powershell
dotnet build .\NetToPlc.slnx -c Release
.\src\NetToPlc.App\bin\Release\net8.0-windows\NetToPlc.exe
```

## 使用流程

1. 启动目标 PLC、PLCSIM 或协议网关，确认其实际监听地址和端口。
2. 在 NetToPLC Bridge 中新建规则，填写本地监听地址、监听端口和目标地址、目标端口。
3. 在“本地监听”中填写运行桥接程序的网卡地址；在“目标 PLC / PLCSIM”中填写 PLC 或协议网关地址。
4. 点击“启动”或“全部启动”。
5. 在 SCADA/HMI 中把 PLC 地址指向本机监听地址和监听端口。

本项目的当前默认规则按以下环境配置：

```text
本机 PLCSIM 网卡：192.168.0.10
PLCSIM 实例 X1： 192.168.0.1
监听端口：       102
EET Pro PLC IP： 192.168.0.10
```

程序首次启动时会创建并启动这条规则。它会以管理员权限短暂重启 `s7oiehsx64` 服务，使 NetToPLC 可以接管 `192.168.0.10:102`，并以 `0, 1` 机架/槽位连接 PLCSIM。

使用前必须按以下方式配置 SIMATIC S7-PLCSIM V21：

1. 下载/加载 PLC 程序，并确保 CPU 可以进入 `RUN`。
2. 保留 PLCSIM 基础版默认的 `PLCSIM Softbus (internal only)` 通信模式，不需要切换为网络适配器模式。
3. 适配器选择 `Siemens PLCSIM Virtual Ethernet Adapter`，确认 PLCSIM 实例的 X1 地址为 `192.168.0.1`。
4. NetToPLC 启动时会自动把 `S7ONLINE` 固定为 `Siemens PLCSIM Virtual Ethernet Adapter.TCPIP.1`，运行和退出后都会保持，不再切回物理网卡。
5. 重新启动 CPU，并确认 `RUN / STOP` 指示为绿色。

EET Pro 的 PLC IP 应填写 NetToPLC 的监听地址 `192.168.0.10`，而不是 PLCSIM 实例内部的 X1 地址。机架/槽位使用 `0/1`。实例未组态或 `STOP` 时，客户端会出现“连接后立刻断开”。

## 架构

```text
SCADA / HMI
    |
    | TCP
    v
NetToPLC Bridge (TcpListener)
    |
    | transparent byte relay
    v
PLC / PLCSIM / protocol gateway
```

`NetToPlc.Core` 负责监听、目标连接、双向数据转发、状态和流量统计。`NetToPlc.App` 只负责配置、运行控制和日志展示。

## 配置示例

```json
{
  "version": 1,
  "startRoutesOnLaunch": false,
  "maxLogEntries": 500,
  "routes": [
    {
      "id": "c2063296-3c30-4c1e-9763-ef81ffbf1047",
      "name": "S7 PLC 网络映射",
      "enabled": true,
      "listenAddress": "192.168.0.10",
      "listenPort": 102,
      "targetAddress": "192.168.0.1",
      "targetPort": 102,
      "connectTimeoutMs": 5000
    }
  ]
}
```

## 验证

项目包含不依赖测试框架的冒烟测试，覆盖配置读写、无效规则校验和真实 TCP 双向转发：

```powershell
dotnet run --project .\tests\NetToPlc.SmokeTests\NetToPlc.SmokeTests.csproj -c Release
```

## 当前范围

程序包含两条后端路径：

- `TCP 透传`：不解析 S7 报文，目标端点必须提供可连接的 TCP 服务。
- `PLCSIM S7Online`：解析 ISO-on-TCP，并通过西门子 S7Online 接口转发到 PLCSIM。

PLCSIM S7Online 后端以管理员权限运行，并需要本机安装兼容的西门子 S7DOS/PLCSIM 组件。

监听 `0.0.0.0` 会把端口暴露给局域网，请在受控网络中使用，并通过 Windows 防火墙限制可访问来源。

## 第三方代码

ISO-on-TCP 与 S7Online 适配层基于 Thomas Wiens 的 NetToPLCsim 项目及 `jybbang/NetToPLCSimLite` 的修改版本，按 GNU Lesser General Public License v3 使用。许可证全文见 `src/NetToPlc.PlcSim/LICENSE-NetToPLCsim.txt`。
