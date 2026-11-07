# naive 与 REALITY 端到端测试报告（2026-11-06）

**状态：** `TESTED`（隔离测试栈；不是生产验收）

**范围：** 同一个测试 Caddy 监听上的网站、naiveproxy 和 REALITY+Vision 三条路径。

**目标版本：** `v0.5.0` 的 REALITY 收口验证。

**结论：** naive 与 REALITY 都通过了端到端可用性、负向安全控制和短时稳定性
测试。naive 最初的空隧道问题已定位为**测试 Caddyfile 的地址形态**，不是凭据、
forwardproxy 二进制或协议本身的问题。REALITY 的握手、外层证书伪装、PROXY v2
和负向凭据控制均通过。测试使用自签证书和隔离端口，因此本文不把结果扩大为生产
隐蔽性或生产验收。

本文不修改 `deploy/`、源码、构建输入或生产配置。测试结束后，临时进程、临时
UFW 规则和临时目录均已清理。

## 1. 测试环境

为避免把运行环境中的真实主机名、公网地址和测试凭据写进仓库，本文使用下表中的
别名。别名与运行环境的对应关系只在本次测试环境存在，测试结束后已删除。

| 别名 | 说明 |
|---|---|
| `<E2E-SERVER>` | 隔离测试服务端，Linux `amd64` |
| `<E2E-CLIENT>` | 测试客户端，Linux `amd64` |
| `<E2E-SERVER_IP>` | 服务端测试入口地址；命令模板中的占位符 |
| `<NAIVE_TEST_SNI>` | 测试 Caddy 自签证书使用的测试 SNI |
| `<REALITY_TEST_SNI>` | 本次指定的 REALITY 外层 SNI/dest；公开网关域名不在仓库中重复 |
| `<UNKNOWN_TEST_SNI>` | 未命中的 SNI；可用 `unknown.test` 代表 |
| `<STABLE_TARGET>` | 稳定性测试使用的公开、稳定的 HTTP 响应目标 |
| `<LARGE_TARGET>` | 大页面目标；本次使用公开 Apple 页面 |
| `<HEADER_ECHO_TARGET>` | 回显请求头的公开目标 |
| `<NAIVE_PROXY_AUTH>` | 一次性测试凭据的占位符；真实值未写入本文 |

服务端测试拓扑：

```text
client
  |
  | TLS :8443, SNI <NAIVE_TEST_SNI> 或 <REALITY_TEST_SNI>
  v
test Caddy
  |-- layer4 matcher: REALITY SNI -> 127.0.0.1:19099, PROXY v2
  |-- forward_proxy: authenticated naive CONNECT
  `-- reverse_proxy: site / decoy path -> 127.0.0.1:18080
```

这里的 Caddyfile 是隔离端口 `8443` 的等价测试拓扑，不是 `deploy/Caddyfile`
原样运行；`deploy/` 冻结内容没有改动。

关键运行版本与身份：

| 项目 | 观测值 |
|---|---|
| 测试 Caddy | `v2.11.7`，带 `forwardproxy` 和 `caddy-l4` 模块 |
| Caddy 测试二进制 SHA-256 | `693057c2f596e163144eb0d2991bd4c8b19cadb351199cb8cc87b183647618f2` |
| 已加载模块 | `http.handlers.forward_proxy`、`caddy.listeners.layer4`、`layer4.handlers.proxy` 等 |
| 服务端 Xray | `26.9.30` |
| 客户端 Xray | `26.10.29` |
| 服务端测试端口 | `8443/tcp`，`19099/tcp`（回环），`18080/tcp`（回环） |
| 客户端测试端口 | REALITY SOCKS `10802`，naive SOCKS `10803` |
| 测试窗口 | 2026-11-06 约 22:40–23:15（Asia/Shanghai） |

测试服务端被隔离在临时目录中，Xray 只监听回环；`8443/tcp` 的 UFW 临时规则只
允许 `<E2E-CLIENT>` 访问。生产 `:443`、生产 Xray、生产站点和生产反向代理没有
参与本次测试，也没有被重启。

## 2. 执行结论

| 维度 | 结论 | 依据 |
|---|---|---|
| 网站角色 | PASS | Caddy 测试站点在 h1 和 h2 下都返回 `200`，测试后端内容为 `mc-e2e-decoy` |
| naive 可用性 | PASS | 正确凭据的直接 CONNECT 和官方 naive 客户端都返回 `200`，出口为服务端 |
| REALITY 可用性 | PASS | 正确 Xray 客户端经 SOCKS 访问公开目标返回 `200` |
| REALITY 伪装 | PASS | 无认证探测得到与真实目标一致的证书；TLS 1.3、ALPN h2 |
| PROXY v2 | PASS | 回环抓包观察到 28 字节 PROXY v2 头，模块日志显示 upstream 为 `127.0.0.1:19099` |
| naive 认证 | PASS | 错误凭据和无凭据都被诱饵路径吸收，没有建立到目标的隧道 |
| REALITY 认证 | PASS | 错误 UUID、错误 publicKey、错误 shortId 三种控制全部失败 |
| 私有目标 ACL | PASS（有协议提示） | Caddy 错误日志 `403 no allowed IP addresses`，没有 upstream 数据 |
| 端口隔离 | PASS | 非客户端来源访问 `8443` 超时；`19099`/`18080` 只绑定回环 |
| 稳定性 | PASS | 30 次串行、8 并发、3 分钟 soak 全部 `200`，错误数为零 |
| 生产就绪性 | NOT VERIFIED | 自签证书、隔离端口和测试 SNI 不能代表生产隐蔽性或长期运行 |

## 3. 测试矩阵

### 3.1 网站与 TLS

| ID | 期望 | 观测 | 判定 |
|---|---|---|---|
| SITE-01 | 测试站点支持 h1 和 h2 | h1 返回 `200`，h2 返回 `200`；内容为 `mc-e2e-decoy` | PASS |
| SITE-02 | 测试服务器只开 h1/h2，不开 h3 | `protocols h1 h2`；没有 UDP `8443` 监听 | PASS |
| TLS-01 | 自签 CA 可被显式信任 | `openssl`/curl 使用测试 CA 时 verify code 为 0 | PASS |
| TLS-02 | 不信任测试 CA 时应失败 | curl exit 60，拒绝自签链路 | PASS（预期失败） |

代表性命令（模板，尖括号值在测试环境中替换）：

```bash
curl --http1.1 --cacert <TEST_CA> \
  --resolve <NAIVE_TEST_SNI>:8443:<E2E-SERVER_IP> \
  -o /dev/null -w '%{http_version} %{http_code}\n' \
  https://<NAIVE_TEST_SNI>:8443/

curl --http2 --cacert <TEST_CA> \
  --resolve <NAIVE_TEST_SNI>:8443:<E2E-SERVER_IP> \
  -o /dev/null -w '%{http_version} %{http_code}\n' \
  https://<NAIVE_TEST_SNI>:8443/
```

### 3.2 naiveproxy

| ID | 期望 | 观测 | 判定 |
|---|---|---|---|
| NAIVE-01 | 正确凭据的直接 CONNECT 应能穿过代理 | 公开小目标返回 `200`，约 1 秒 | PASS |
| NAIVE-02 | 官方 naive 客户端应可使用同一端点 | SOCKS `10803` 访问公开大页面返回 `200`，约 254292 字节 | PASS |
| NAIVE-03 | 错误凭据不得建立到目标的隧道 | `501 Not Implemented` 的诱饵响应；没有目标数据 | PASS（fail closed） |
| NAIVE-04 | 无凭据不得建立到目标的隧道 | 与 NAIVE-03 相同，落到诱饵路径 | PASS（fail closed） |
| NAIVE-05 | 私有目标应被 ACL 拒绝 | Caddy 错误日志 `403 no allowed IP addresses`；没有 upstream 数据 | PASS（见 F-03） |
| NAIVE-06 | 目标端不得看到代理注入的来源头 | 回声目标只看到 `Accept`、`Host`、`User-Agent` | PASS |

代表性命令（测试凭据必须使用一次性值，不要复用生产凭据）：

```bash
curl --proxy https://<NAIVE_TEST_SNI>:8443 \
  --proxy-cacert <TEST_CA> \
  --proxy-basic --proxy-user '<NAIVE_PROXY_AUTH>' \
  --resolve <NAIVE_TEST_SNI>:8443:<E2E-SERVER_IP> \
  -o /dev/null -w '%{http_code} %{time_total}\n' \
  https://<STABLE_TARGET>/

curl --proxy https://<NAIVE_TEST_SNI>:8443 \
  --proxy-cacert <TEST_CA> \
  --resolve <NAIVE_TEST_SNI>:8443:<E2E-SERVER_IP> \
  -o /dev/null -w '%{http_code}\n' \
  https://<STABLE_TARGET>/
```

`NAIVE-03` 和 `NAIVE-04` 的 HTTP 状态来自诱饵站点，不等于代理认证成功；测试
以响应体、目标数据和 Caddy 日志三者共同判定，而不是只看状态码。

### 3.3 REALITY+Vision

| ID | 期望 | 观测 | 判定 |
|---|---|---|---|
| REALITY-01 | 正确客户端应能建立 VLESS/REALITY 隧道 | SOCKS `10802` 返回 `200`，大页面 254292 字节 | PASS |
| REALITY-02 | 无认证探测应得到真实目标的证书 | 证书 subject、issuer、有效期和指纹与真实目标一致 | PASS |
| REALITY-03 | layer4 应向 Xray 发送 PROXY v2 | 抓包头部为 `0d0a0d0a000d0a515549540a...`，命令字节为 PROXY | PASS |
| REALITY-04 | 错误 UUID 不得建立隧道 | 客户端 TLS 失败，未返回 `200` | PASS（预期失败） |
| REALITY-05 | 错误 publicKey 不得建立隧道 | 连接 reset，未返回 `200` | PASS（预期失败） |
| REALITY-06 | 错误 shortId 不得建立隧道 | 连接 reset，未返回 `200` | PASS（预期失败） |
| REALITY-07 | 未知 SNI/无 SNI 不应误入 REALITY | 回落到 Caddy 站点证书 `CN=<NAIVE_TEST_SNI>` | LIMITATION（见 F-04） |

REALITY 证书探测模板：

```bash
openssl s_client -connect <E2E-SERVER_IP>:8443 \
  -servername <REALITY_TEST_SNI> -alpn h2 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -fingerprint -sha256 -dates
```

PROXY v2 抓包模板：

```bash
tcpdump -i lo -nn -s0 -c 8 -w proxyv2.pcap 'tcp port 19099'
# 在客户端发起一次 REALITY 请求后：
tcpdump -nn -r proxyv2.pcap -X | grep -a -E '0d0a 0d0a|QUIT'
```

### 3.4 端口与访问边界

| ID | 期望 | 观测 | 判定 |
|---|---|---|---|
| NET-01 | `8443/tcp` 只允许测试客户端 | 客户端成功；非客户端来源连接超时；UFW 临时规则仅允许 `<E2E-CLIENT>` | PASS |
| NET-02 | `19099/tcp` 不对外暴露 | 只监听 `127.0.0.1`；外部连接超时 | PASS |
| NET-03 | `18080/tcp` 不对外暴露 | 只监听 `127.0.0.1`；外部连接超时 | PASS |
| NET-04 | 测试 Caddy 不应恢复 h3 | 测试 `ss` 没有 UDP `8443`；UFW 也没有 `8443/udp` 规则 | PASS |

### 3.5 客户端启动模板

以下只展示测试拓扑，不包含真实凭据或密钥。实际测试值由一次性环境变量注入，
测试结束后已删除。

naive 客户端示意：

```bash
naive --listen=socks://127.0.0.1:10803 \
  --proxy=https://<NAIVE_USER>:<NAIVE_PROXY_AUTH>@<NAIVE_TEST_SNI>:8443
```

Xray 客户端示意（只列出 REALITY 相关字段）：

```json
{
  "inbounds": [{
    "port": 10802,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {"udp": true}
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "<E2E-SERVER_IP>",
        "port": 8443,
        "users": [{
          "id": "<VLESS_UUID>",
          "encryption": "none",
          "flow": "xtls-rprx-vision"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "<REALITY_TEST_SNI>",
        "fingerprint": "chrome",
        "publicKey": "<REALITY_PUBLIC_KEY>",
        "shortId": "<REALITY_SHORT_ID>"
      }
    }
  }]
}
```

`<VLESS_UUID>`、`<REALITY_PUBLIC_KEY>` 和 `<REALITY_SHORT_ID>` 是占位符，不是
本次实际值。服务端对应的私钥、UUID 和 shortId 只在测试进程环境中使用，没有写入
仓库或本报告。

### 3.6 稳定性

稳定性测试使用 `<STABLE_TARGET>`，因为它能快速返回一个小响应，避免把上游大页面
或 IPv6 出口的偶发问题误判为代理故障。

| ID | 场景 | naive | REALITY |
|---|---|---|---|
| STAB-01 | 30 次串行 | 30/30，p50 0.899s，p95 0.956s | 30/30，p50 0.751s，p95 0.809s |
| STAB-02 | 8 并发 | 8/8，p50 0.891s，p95 0.953s | 8/8，p50 0.742s，p95 0.799s |
| STAB-03 | 3 分钟 soak，每 5 秒一次 | 36/36，p50 0.902s，p95 0.942s | 36/36，p50 0.755s，p95 0.821s |
| STAB-04 | 客户端错误数 | 0 | 0 |

soak 期间没有观察到客户端失败；naive 进程 RSS 约 11 MB，客户端 Xray RSS 约
31–35 MB。服务端测试 Caddy 约 51 MB，服务端测试 Xray 约 38 MB。短时数据没有
显示内存持续增长。

测试 Caddy 的服务端日志中可解释的错误类别为：

- 5 条 layer4 `EOF`：无 SNI/未知 SNI 探测在匹配阶段结束；
- 2 条 `http2: stream closed`：客户端主动关闭 CONNECT；
- 2 条 Apple IPv6 出口 reset：公开 Apple 大页面的目标侧问题，重试后成功。

这些错误没有出现在 `<STABLE_TARGET>` 的 30/8/soak 测试中。

## 4. 关键发现

### F-01 非 443 测试配置的地址形态（已修复测试配置）

最初的临时测试站点点为：

```caddyfile
<NAIVE_TEST_SNI>:8443 {
```

该形态下 naive CONNECT 得到 `200`/`NOP`、空响应或内层 TLS close notify。最小对照
实验中，相同形态在非 443 端口失败；改成同时写地址优先形式和带端口主机名后立刻
恢复：

```caddyfile
:8443, <NAIVE_TEST_SNI>:8443 {
```

同时显式写入 `protocols h1 h2`，确保测试栈不会恢复 h3。

这是**测试夹具**问题，不是 `deploy/Caddyfile` 的问题：交付形态使用 `:443,
a.test`，第二项默认就是同一个 `:443`，不存在这个非标准端口陷阱。非 443 的测试
配置应把两个地址都写成同一端口；建议把它固化为回归测试，而不是只写在文档里。

### F-02 `probe_resistance` 目标与代理目标同名

测试配置使用 `probe_resistance example.com`。当测试目标也设为 `example.com:443`
时，即使携带正确凭据，也会得到 Caddy 的代理 `200` 响应后接诱饵明文页面，内层
TLS 报 `wrong version number`，没有目标数据。这不是认证成功的反例，而是诱饵目标
与代理目标发生碰撞。

结论：测试和部署都必须保证 `probe_resistance` 域名不等于测试/常用代理目标；
CO-8 的约束应继续作为机器断言存在。诱饵后端在测试中返回了 Python 静态服务器的
`501`，生产诱饵则需要独立的、看起来合理的站点内容。

### F-03 私有目标被 ACL 拒绝，但客户端先看到 200

正确凭据访问 `127.0.0.1:18080` 时，curl 看到代理 `200` 头，随后得到空响应。
服务端错误日志明确记录：

```text
403 no allowed IP addresses for 127.0.0.1
forwardproxy.Handler.dialContextCheckACL
```

没有 upstream 数据，也没有建立到私有目标的隧道。安全结论是 PASS，但客户端看到
的 `200` 后空响应是 forwardproxy 的协议表现；回归测试应对响应体、upstream 日志
和 ACL 错误都做断言，不能仅用 `200` 判定成功。

### F-04 未知 SNI/无 SNI 回落到站点证书

对测试 `8443` 使用未知 SNI 或省略 SNI 时，layer4 不命中 `<REALITY_TEST_SNI>`，
流量落到 Caddy 网站角色，返回自签证书：

```text
subject=CN=<NAIVE_TEST_SNI>
issuer=CN=MC E2E Test CA
```

这不是认证绕过，但属于隐蔽性限制：主动探测者可以通过随机 SNI 看到一个站点证书，
而不是只看到 REALITY 目标的证书。生产形态是否接受这一回落，需要单独评估默认
证书、拒绝策略或诱饵策略；本次没有修改冻结的 `deploy/`。

### F-05 公开 Apple 目标的 IPv6 出口 reset

naive 的一次大页面请求曾因服务端 IPv6 出口出现
`read: connection reset by peer` 超时，后续重试成功。Caddy 日志显示 reset 发生在
服务端到公开目标的 IPv6 连接上，不是客户端到 Caddy 的握手。稳定性测试因此使用
稳定的 IP 回声小目标；报告不把该上游网络问题记作 naive 失败。

### F-06 生产 `:443` 的 h3 观察

隔离测试栈的 `8443` 没有 UDP 监听；生产服务端的 `:443` 仍同时监听 UDP/443。
仓库设计只开 h1/h2，因此生产 h3 是独立的交付观察项，不应在本次测试中静默修改。
需要单独决定是否关闭生产 h3，并用生产变更流程验证。

### F-07 测试用途限制

本次按测试要求使用：

- 自签测试证书；
- 非标准 `8443` 测试端口；
- 用户指定的 REALITY 外层测试 SNI/dest；
- 临时生成的认证值、UUID、publicKey 和 shortId（全部未写入本文）。

Xray 对测试 SNI 和非 443 端口给出风险警告，这是测试参数的风险提示，不是本报告
对生产参数的推荐。自签证书不具生产隐蔽性，测试诱饵后端也不是生产诱饵。

发布自动化的架构结论不变：本次只验证 Linux `amd64`。`arm64` 是可选发布矩阵，
不是本项目的运行前提；如果没有 arm64 使用需求，默认只构建/发布 `amd64` 即可，
不要让 arm64 工作流阻塞 `v0.5.0`。

### F-08 本次没有覆盖的威胁面

以下项目没有被本次测试证明安全或不安全，不能从本报告推导出生产结论：

- 长时间、持续的大流量和资源耗尽测试；本次只有 30 次、8 并发和 3 分钟 soak；
- 主动探测、暴力尝试和速率限制；本次只验证少量错误凭据/错误密钥控制；
- DPI、TLS-in-TLS 流量特征、包大小/时序指纹和机器学习分类；
- 轮换凭据、密钥泄漏后的恢复流程和重放防护；
- 生产证书链、生产诱饵内容、CDN、上游故障切换和 IPv6 双栈行为；
- 真实审查环境下的可达性；本次只验证隔离网络中的可达性。

功能可用性和已列出的负向控制可以据此报告判定；**生产隐蔽性和完整安全性不能据此
报告判定**。

## 5. 清理与后置条件

| ID | 检查 | 结果 |
|---|---|---|
| CLEAN-01 | 测试 Caddy、测试 Xray、诱饵后端 | 已停止；`8443/19099/18080` 无测试监听 |
| CLEAN-02 | 临时 UFW 规则 | 已删除；没有残留的 `8443` 允许规则 |
| CLEAN-03 | 服务端 `/tmp` 测试目录和脚本 | 已删除 |
| CLEAN-04 | 客户端 naive/Xray SOCKS | 已停止；`10802/10803` 消失 |
| CLEAN-05 | 客户端临时目录 | 已删除；客户端 MySQL 仍为 `inactive` |
| CLEAN-06 | 本地临时 CA/凭据目录 | 已删除 |
| CLEAN-07 | 生产服务 | Caddy、nginx、Xray 仍为 `active`；生产端口保持不变 |

本次没有修改仓库源码、`deploy/`、构建输入或生产配置。文档之外没有留下测试凭据、
测试密钥或测试服务。

## 6. 建议的后续工作

1. 在测试夹具中加入“非 443 端口必须使用 `:port, host:port`”的守卫，避免再次
   把测试配置错误误判为 naive 协议故障。
2. 把私有目标 ACL 的断言从“状态码”升级为“没有 upstream 数据、没有目标响应、
   日志出现 403 ACL 错误”。
3. 保留并强化 `probe_resistance` 目标不等于测试/代理目标的负向断言。
4. 单独评估生产 `:443` 的 h3 策略；本次不修改生产。
5. 评估未知 SNI/无 SNI 的默认证书回落，决定是否需要拒绝或更合适的诱饵行为。
6. 发布自动化默认 `amd64`；`arm64` 保持手动或可选，不阻塞 `v0.5.0`。

## 7. 证据说明

本文记录的是测试运行中的命令、观测值和判定。测试结束后，临时目录和临时凭据已按
要求清理；原始 `pcap`、访问日志和 CA 私钥没有保留在仓库或本地临时目录。本文中的
真实主机地址、SNI 和凭据均以别名表示，实际对应值只存在于已删除的测试环境。

如果要把本报告升级为正式发布证据，应在新的 GSD/evidence 任务中重新采集并脱敏
原始日志，而不是把本报告当成原始捕获的替代品。
