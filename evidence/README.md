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
