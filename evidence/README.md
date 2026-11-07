# `evidence/` — 发布子集的脱敏副本

本目录是 `.gate/release/` 中**发布子集**的**脱敏副本**，不是重新采集的产物，也不是对
未留存内容的补写。每个文件的**行数与非脱敏原件完全一致**，唯一的差异是 token 被替换为
别名（见 `.gate/release/REDACTION-MAP.md`）。

## 来源与方法

- 输入：`D:/AiWork/Qoder/my-caddy/.gate/release/`（只读，未改动）
- 脚本：`D:/AiWork/Qoder/my-caddy/scripts/redact-evidence.sh <IN_DIR> <OUT_DIR>`
- 运行：`bash scripts/redact-evidence.sh .gate/release evidence`
  - stdout：`redact-evidence.sh: 23 file(s) redacted into evidence/`
  - stderr：空
  - 退出码：`0`
- 别名空间：`<HOST-1>`…`<HOST-7>`、`<PUBLIC_IP-1>`…`<PUBLIC_IP-6>`（共 13 行，
  与 `REDACTION-MAP.md` 的 13 行一一对应）
- 幂等：同一输入连跑两次，`diff -r` 为空，sha256 汇总一致
  （`6ee84e2e2148408536552a4284707cb2150f821ff2a8b9af4e17661462a9f878`）

## 索引（23 个必发文件，逐条）

行数列为**本目录副本的行数**；每个都与 `.gate/release/` 原件相等（已在
`.gate/release/SP7-EVIDENCE.md` 的 §B.6-4 中逐条比对）。

| # | 文件 | 行数 | 用途 |
|---|------|------|------|
| 1 | `SP4-D1.txt` | 177 | 交付形态（站点级 `basic_auth`）下 `GET /` 返回 `HTTP/2 401` 而 overlay B 返回 `HTTP/2 200` + `x-site: v4`，据此证明 D1 是交付配置的真实缺陷而非测法问题 |
| 2 | `SP4-D2.txt` | 81 | 带 `Proxy-Authorization` 的 naive `CONNECT` 实际返回 `HTTP/1.1 200 OK`（不是 `200 Connection established`），并以隧道内中继的内层请求证明隧道成立 |
| 3 | `SP4-D3.txt` | 108 | handler 顺序前导：`forward_proxy` 必须排在站点 handler 前，含全局 `order` 行有无两种写法下 `proxy-authenticate` 命中数为 0 |
| 4 | `SP4-D4.txt` | 99 | 凭据一致性（一次性测试口令的 `sha256sum`）与 90 秒存活隧道：`START`/`CHECK` 相隔 `DELTA_SECONDS=90`、`ALIVE=1`、无 `eof/closed/errno` |
| 5 | `SP4-D5.txt` | 205 | 无 `acl` 覆盖时默认私网拒绝生效：拒绝的 CONNECT 回 `200 OK` 但仅 149 字节响应头、后端日志零增长，并以 `acl { allow 127.0.0.1/32 }` 测试副本做正对照 |
| 6 | `SP4-D6.txt` | 185 | `diff -u Caddyfile.b Caddyfile.v2` 显示两变体唯一差异是 `probe_resistance`，并记录两变体各 6/6 探针 0 次 `407`／`Proxy-Authenticate` |
| 7 | `SP4B-D1.txt` | 79 | 只替换两个凭据占位符后的交付形态（`diff` 在文件内）下站点角色应答 `HTTP/2 200` + `X-Site: v4` + `SITE-BODY-v4`，无 `www-authenticate`／`Proxy-Authenticate` |
| 8 | `SP4B-D2.txt` | 77 | naive CONNECT 的状态行与 `Padding:`/`Alt-Svc` 头，以及隧道内层 `GET /` 取回源站整页（约 201,691 字节，随运行浮动）的中继证据 |
| 9 | `SP4B-D5.txt` | 127 | acl 拒绝的 CONNECT 四个独立观测量（`Padding:` 诱饵、`captured_bytes=149`、后端日志前后均为零、acl 正对照新增 `GET /from-control`） |
| 10 | `SP5-C1.txt` | 148 | B 侧收到的字节是原始 TLS ClientHello，Caddy 未解密 —— layer4 透传的直接证据 |
| 11 | `SP5-C2.txt` | 209 | 真实客户端 IP 出现在 xray 访问日志中，PROXY protocol 未丢失来源地址 |
| 12 | `SP5-C3.txt` | 166 | PROXY 是成对语义：单端配置被拒，两端都关则退化为 socket 地址 |
| 13 | `SP5-C4.txt` | 28 | `xray version >= v1.8.0` 的版本核对输出 |
| 14 | `SP5-C5.txt` | 60 | `acceptProxyProtocol` 恰好出现一次且位于 `streamSettings.sockopt` |
| 15 | `SP5-C6.txt` | 53 | xray 仅监听回环地址（`ss` 表） |
| 16 | `SP6-F1.txt` | 119 | 站点 H3 连通性（含 `github.com/klzgrad` 的开源引用，属允许集 `[C2]`） |
| 17 | `SP6-F2.txt` | 165 | naive 的 H3 路径未被破坏；文件内含 `naive-client.json` 的运行口令，其 `"proxy"` 行（`:49`）用户信息位的值已替换为 `<NAIVE_PASSWORD>`；同一文件 `:8` 正文里的 `quic://user:<password>@a.test:443` 是原件自带的尖括号指代形态（尖括号内是普通占位词，非运行口令），本目录未改动。本文件内不存在 `<NAIVE_CREDENTIALS>`（该占位符只出现在 `adapted.json`） |
| 18 | `SP6-F3.txt` | 155 | 未知 SNI：不崩溃、不误路由（回落到默认站点） |
| 19 | `SP6-F4.txt` | 110 | B 命中 layer4 但上游宕机时无回落 |
| 20 | `SP6-F5.txt` | 136 | B 未命中 layer4 时交付配置的 404 隔离行为 |
| 21 | `verify-run.log` | 20 | 一次 `scripts/verify.sh` 运行的日志尾部：`ITEM S3-1`…`S3-11 PASS`、`ITEM S7-1`…`S7-8 PASS`，末行 `VERIFY: PASS` |
| 22 | `adapted.json` | 1 | 适配后的 Caddy 配置 JSON；凭据字段已脱敏为 `"auth_credentials":["<NAIVE_CREDENTIALS>"]` |
| 23 | `adapt.err` | 0 | 适配步骤的 stderr 捕获，**0 字节**（见下节） |

索引文件自身也在此目录：`README.md`（本文件），不计入 23 个必发项。

## 已知失真：`SP4-D4.txt:14` 的命令

`SP4-D4.txt` 第 14 行是一条 `grep … 'basic_auth …' | awk …` 管道命令。脱敏后命令中的模式字段已被替换，原命令以 `.gate/release/` 原件为准；该行引号已不配对，不能直接重跑。本轮不修归档内容本身（修它就不再是「副本」）。

## SP1／SP2／SP3：无留存产物

- **SP1：无留存产物。** SP1 阶段的产出是仓库骨架与模板（本目录没有任何 SP1 命名的原始捕获），
  当时未落盘任何可发布的运行输出。重新得到：从 `docs/BUILD.md` 的骨架说明与仓库现有文件结构
  反推当时的目录约定；SP1 没有可重跑的运行命令，因此**不提供重跑方式**，也不新建 `SP1-*.txt`。
- **SP2：无留存产物。** 当时的双架构构建输出未留存。重新得到：按 `docs/BUILD.md` 跑双架构构建
  （`linux/amd64` 与 `linux/arm64` 各一次），构建产物的 sha256 即为该阶段的凭据。
- **SP3：无留存产物。** 当时的离线校验输出未留存。重新得到：按 `docs/VERIFY.md` 跑离线校验
  （`bash scripts/verify.sh`），其尾部 `PASS` / `VERIFY:` 行为该阶段结论。

以上三条均**不新建**占位文件；`evidence/` 中不存在任何 `SP1-`、`SP2-`、`SP3-` 前缀的文件。

## `adapt.err` 的处置

`adapt.err` 是 **0 字节，原始捕获为空**（对应 SPEC 的 B-21）。它仍按发布清单发布，理由：
「stderr 为空」本身是一条可审的结论 —— 适配步骤没有向 stderr 写任何内容，静默丢弃会让审计者
无法区分「没有错误」与「没有采集」。重新得到它的命令（在产生该捕获的环境中执行）：

```sh
# 适配步骤本身；stdout 进 adapted.json，stderr 进 adapt.err
<适配命令> > adapted.json 2> adapt.err
```

`evidence/adapt.err` 与 `.gate/release/adapt.err` 同为 0 字节，行数一致（0 = 0）。

## 条件发布：三个冲刺总结未发布

SPEC 的条件发布项是 `SPRINT4-SUMMARY.md`、`SPRINT5-SUMMARY.md`、`SPRINT6-SUMMARY.md`
——**仅当通过与 23 个必发文件同样的扫描才发布**。本轮判定：**未发布（未过扫描）**。

| 文件 | 结论 | 原因 |
|------|------|------|
| `SPRINT4-SUMMARY.md` | 未发布（未过扫描） | 正文含字面 IPv4 地址两处（第 1 行；第 73 行），既非环回也未走别名空间。它是 `*.md`，`redact-evidence.sh` 按设计跳过 `*.md`，不会被脱敏 |
| `SPRINT5-SUMMARY.md` | 未发布（未过扫描） | 正文含字面 IPv4 地址（第 19 行与第 49–51 行，同一台后端机器）。同为 `*.md`，脚本跳过、不会脱敏 |
| `SPRINT6-SUMMARY.md` | 未发布（未过扫描） | 正文含字面 IPv4 地址（第 82 行，与 SPRINT5 同一台后端机器）。同为 `*.md`，脚本跳过、不会脱敏 |

三个文件都留在 `.gate/release/` 原件位置，未删除、未改动；本目录没有任何副本。
被扫描器命中的地址原文就留在原件的上述行，按下面的命令可复现判定，本 README 故意不复制这些字面量
（否则 `evidence/` 自身就会触发 §B.6-5 的公网点分 IP 扫描）：

```sh
grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}' .gate/release/SPRINT4-SUMMARY.md .gate/release/SPRINT5-SUMMARY.md .gate/release/SPRINT6-SUMMARY.md
```

## 绝不发布的名单

文件名以 `PM-`、`notes-`、`PUBLISH-`、`GRADE-` 开头的一律不发布。本目录中此类文件数量为 **0**。

## 已知限制：该字符串为普通词，非凭据

`evidence/SP4-D1.txt:95`、`evidence/SP6-F2.txt:8`、`evidence/SP6-F5.txt:43` 三处出现同一个小写英文单词：`:95` 落在 Caddy 安装本地 CA 的固定提示语里，`:8` 是原件自带的尖括号指代形态，`:43` 是 diff 注释里的普通叙述词。**该字符串为普通词，非凭据。**

依据是它被编译进 Caddy 自身：`dist/caddy-linux-amd64` 与 `dist/caddy-linux-arm64` 各命中 52 次，且出现在 Caddy 的提示串中（如 `(you might be prompted for …)`、`The … to hash`、`username and … cannot be empty`）。每轮运行的口令不会出现在厂商二进制的字符串表里，更不会两个架构命中数完全相同。三处的 `od -c` 原始字节与逐处定性见 `.gate/release/F9-REPORT.md` 的 F-10 一节。

## E2E 报告（2026-11-06）—— 索引，不是证据副本

`docs/E2E-NAIVE-REALITY-2026-11-06.md` 是一次**隔离测试栈**上的 naive + REALITY
端到端实测报告，不是本目录的脱敏副本，也没有对应的原始捕获。它记在这里是为了让审计者
从证据索引也能找到它，并同时看到它的边界：

- 拓扑：客户端 → 测试 Caddy `:8443` → layer4（REALITY SNI → `127.0.0.1:19099`，
  PROXY v2）／`forward_proxy`／`reverse_proxy`。
- 被测二进制：`v0.4.3` 发布资产，sha256 `693057c2…618f2`。
- 结论：REALITY-01…07、NAIVE-01…06、SITE/TLS/NET/STAB/CLEAN 各断言组按报告所述通过；
  REALITY-07 标注为 LIMITATION。
- 未留存：原始日志与 pcap。报告第 7 节明确说明「报告不能当作原始捕获」，因此本目录
  **不新增**任何 `v0.5.0` 之前的 E2E 文件，也不从报告正文回填日志。
- 未证明：自签证书、非 443 端口、测试 SNI 都不代表生产隐蔽性；长时压测、主动探测、
  DPI、密钥轮换均未覆盖。

把它变成可重复门禁的工作在里程碑 `v0.5.0`（`E2E-01`…`E2E-04`），届时原始日志会先落
`.gate/`，再用 `scripts/redact-evidence.sh` 生成 `evidence/v0.5.0/`。

## v0.4.3 — 运行时验收证据（2026-11-05）

- 输入：`.gate/v043/`（只读，未改动）
- 命令：`bash scripts/redact-evidence.sh .gate/v043 evidence/v0.4.3`
  - stdout：`redact-evidence.sh: 4 file(s) redacted into evidence/v0.4.3`
  - stderr：空；退出码：`0`
- 文件数：**5** —— `redact-evidence.sh` 产出 4 个脱敏副本，另加 1 个从 ARM64 job log 提取的执行记录
- 行数校验（副本 / 原件）：`ci-runs.txt` 8/8、`coexist-8.log` 9/9、`host.txt` 20/20、`verify-26.log` 28/28
- 幂等：同一输入连跑两次，`diff -r` 为空
- 归档哈希（5 个文件）：`sha256sum evidence/v0.4.3/* | sha256sum` = `4521633caa8fa5c2265bb8abea11abf7035d0d503da2bdfed7a76eef49a19464`
- 别名空间：沿用 `<HOST-1>`…`<HOST-7>` 与 `<PUBLIC_IP-1>`…`<PUBLIC_IP-6>`；本轮新增 `<HOST-8>`，用于 `uname -a` 打印的裸机器名 —— 它不含点，域名扫描看不见它，只有别名表能替换

| # | 文件 | 行数 | 用途 |
|---|------|------|------|
| 1 | `ci-runs.txt` | 8 | 五个绿灯 run、两个负向对照 run、PR 链接 |
| 2 | `coexist-8.log` | 9 | `ITEM CO-1`…`ITEM CO-8` 与 `COEXIST: PASS` |
| 3 | `host.txt` | 20 | 机器名（别名化）、uid、commit `b60f042`、**release 资产**的 sha256、四个端口的事前样本 |
| 4 | `verify-26.log` | 28 | 26 条 `ITEM` 加 `PASS=26 FAIL=0` 与 `VERIFY: PASS` |
| 5 | `arm64-release.log` | 47 | ARM64 实机执行：`aarch64`、资产 sha256、26 条 offline 与 8 条 coexist 结果 |

### 本轮的两处已知差异

1. `RTA-DISPOSITIONS.md` 是 `*.md`，`redact-evidence.sh` 按设计跳过 markdown，因此它**不在**本目录。它不含 IPv4、UUID、userinfo 或凭据，原件仍在 `.gate/v043/`，由 `docs/VERIFY.md` 引用。
2. 幸存者扫描原先会把验证器的计数器行判成“键值凭据”，因为它匹配裸 `PASS` 后跟等号。该行是计数，不是口令，重写规则本来就不动它；扫描现在对该**精确形态**豁免，而 `PASSWORD`、`DB_PASS` 或非数字 `PASS` 后面的键值仍会被拦下（`scripts/redact-evidence.sh`）。

### 采集对象：发布资产本身

第一版归档采集的是本地构建的二进制（sha256 `1a9115…2624`）。发布后核对发现 GitHub release
里的资产是**另一次构建**：`scripts/build.sh` 把 `caddy-l4` 的 `L4_REF` 默认为 `refs/heads/master`，
该分支头在两次构建之间从 `f607ccea…` 前进到 `96e1a6bf…`，因此发布件的 sha256 是
`693057c2f596e163144eb0d2991bd4c8b19cadb351199cb8cc87b183647618f2`。

按“证据必须描述被发布的那个对象”的原则，两个套件已用**下载回来的 release 资产**在 `hw-gz`
重跑：`PASS=26 FAIL=0`、`CO-1..CO-8 PASS`。本目录的副本即这一次采集，commit 为 `b60f042`。
该漂移已记入 `docs/BUILD.md` 的 fork-ref 说明与本轮小结；随后在 `pins/build-inputs.env`
中钉死两个 fork 的提交，并用一次真实 CI 构建确认产物哈希仍为 `693057c2…618f2`。

### ARM64 实机执行（2026-11-06）

ARM64 资产不再只是“结构校验”。手动工作流 `verify-arm64-release` 在 GitHub 托管的
`ubuntu-24.04-arm` runner 上执行了已发布的 v0.4.3 资产：

- run：<https://github.com/olst57/my-caddy/actions/runs/42228779590>，commit `820b890`
- `runner_arch=aarch64`，`go version go1.26.10 linux/arm64`
- 执行前校验 sha256：`76760bdf0ebf3447246806dbc8f18ee6a89871423625dec0a3b0d5798f9abd36`
- `PASS=26 FAIL=0`、`VERIFY: PASS`、`ITEM CO-1`…`ITEM CO-8`、`COEXIST: PASS`
- 本目录的 `arm64-release.log` 是从该 job 的日志中按行提取的，未改动内容

这次执行证明**发布资产能在真实 aarch64 上运行并通过两套门禁**；它不证明 arm64
重建与发布字节一致，后者仍未建立。

### 扫描结果

- 字面 IPv4：无（除 `127.0.0.1`、`0.0.0.0`，本目录内也没有）
- UUID 形状：无
- URL userinfo 形态（`scheme://user:` 后跟非占位值再跟 `@`）：无
- 主机形态 token：`docs/REDACTION.md` C2 允许的模块路径、内核版本串 `6.8.0-136-generic`、版本号 `v0.4.3`

## v0.5.0 — REALITY 收口与 E2E/烟测证据（2026-11-07）

- 输入：`.gate/v050/capture/`（只读，未改动）
- 命令：`bash scripts/redact-evidence.sh .gate/v050/capture evidence/v0.5.0`
  - stdout：`redact-evidence.sh: 5 file(s) redacted into evidence/v0.5.0`
  - stderr：空；退出码：`0`
- 文件数：**5** 个脱敏副本，另加 1 个手写的 `index.md`（`*.md` 按设计跳过，不由脚本产出）
- 行数校验（副本 / 原件）：`caddy-sha256.txt` 2/2、`coexist-8.log` 10/10、`e2e-items.log` 20/20、`smoke-counts.log` 6/6、`verify-26.log` 29/29
- 幂等：同一输入连跑两次到临时目录，`diff -r` 为空
- 归档哈希（5 个脱敏文件，不含 `index.md`）：`sha256sum evidence/v0.5.0/{caddy-sha256,coexist-8,e2e-items,smoke-counts,verify-26}* | sha256sum` = `35e1511a2c571fdb550be2f5cc02fb0c3873db058c891aaa78476a5cf1ddaf0b`
- 别名空间：本轮没有出现新的主机名或公网地址，`<HOST-1>`…`<HOST-8>` 与 `<PUBLIC_IP-1>`…`<PUBLIC_IP-6>` 均未新增

| # | 文件 | 行数 | 用途 |
|---|------|------|------|
| 1 | `caddy-sha256.txt` | 2 | 本次运行所用二进制（go1.26.9 构建）的 sha256 |
| 2 | `coexist-8.log` | 10 | `ITEM CO-1`…`ITEM CO-8` 与 `COEXIST: PASS` |
| 3 | `e2e-items.log` | 20 | 11 条 `ITEM E2E-xx PASS`、三条 `E2E-07 BASELINE` 的 `reject` 观测、两项正对照与 `E2E: PASS` |
| 4 | `smoke-counts.log` | 6 | 四条 `SMOKE` 计数行与上游佐证（`reality_requests=38`、`naive_records=38`） |
| 5 | `verify-26.log` | 29 | 26 条 `ITEM` 加 `PASS=26 FAIL=0` 与 `VERIFY: PASS` |

### 本轮的两处已知差异

1. E2E 捕获是**逐行摘录**：保留每条 item、posture、control 与结论行，但去掉了详细的证书转储。完整日志留在 `.gate/`，因为它带着第三方站点的证书转录，那不是本仓库的证据。
2. 本轮没有 `host.txt`：机器类别、端口与 commit 已写进每个文件首行的 `[capture]` 出处行，因此没有再单独采集一份主机清单。

### 未归档的负向对照

同一套件另跑了一次，把 naive 烟测的目标改成投递 ACL 拒绝的地址：其余十项保持绿色，只有 `E2E-08` 变红（`naive serial 30/30 failures`、`naive concurrent 8/8 failures`、`naive_records=0`）。红跑的日志不进入证据目录——红跑不是发布证据，只用来证明该项对 ACL 敏感。原件在 `.gate/v050/e2e-p6neg.full.log`。

### 扫描结果（本目录）

- 字面 IPv4：无
- 域名形态 token：无
- UUID 形状：无
- URL userinfo 形态：无
- 键值凭据形态：无（S7-12 通过）

### `v0.5.0` 发布资产（2026-11-07）

| 资产 | 大小 | sha256 |
|---|---:|---|
| `caddy-linux-amd64` | 53,022,882 | `c780d1d63fa72b355f28ff7625968860dd9f36294ec884ca3b34920126bd04a8` |
| `caddy-linux-arm64` | 49,414,306 | `8fcd7377649d9351ce0e7b2b42d9a890bcfc16cc0fd6a3d7e7ee1e16bf1c1b49` |
| `SHA256SUMS` | 168 | `083f0c8310ccda5d7661c2a3789f68ec078c5cd06558b600f2bc57b833ee9f57` |
| `pins.txt` | 267 | `677b2813466aa721d38a32d105e19c49f2ccba39abcd4d334deb8138040aed34` |

- 三条独立读数一致：release API 的 asset digest、下载回来的 `SHA256SUMS`、以及 `verify` 工作流在 `d3c19c3` 上按固定输入构建的二进制，都是 `c780d1d6…`。
- 该 CI 二进制正是两套门禁跑过的对象：`offline` 打印 `PASS=26 FAIL=0` 与 `VERIFY: PASS`，`coexist` 下载同一工件后打印 `ITEM CO-8 PASS` 与 `COEXIST: PASS`（run 42369088803）。发布构建 run 42370444867 的 `preflight`/`build`/`publish` 全部成功。
- 53 MB 的 amd64 资产**没有**在本轮于 Linux 测试机执行：到发布 CDN 的速率在编写机约 5–35 KB/s、在测试机约 19 KB/s，传输需要数十分钟到数小时。本目录所有运行时数字来自本地构建的 `872caeee…`；在测试机上执行发布资产记为延期项，不作为已完成。
