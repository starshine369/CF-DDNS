# Cloudflare DDNS 自动化更新脚本 (双栈多域名)

这是一个功能强大的 Cloudflare DDNS (动态域名解析) 更新脚本。经过全面重构，现已支持 **IPv4/IPv6 混合双打**、**跨多个主域名管理** 以及 **真正的“一键无脑装”**。

## ✨ 核心特性

* 🤖 **全自动部署**: 自动检测并安装所需依赖 (`jq`, `curl`, `cron`)，自动将自身部署到系统环境，无需手动折腾。
* 🌍 **双栈混合解析**: 智能获取本机的 IPv4 和 IPv6 地址，支持为不同的子域名独立分配 `A` 或 `AAAA` 记录。
* 🏢 **多主域名 (Zone) 支持**: 突破单个域名的限制，支持在一个脚本中无限次添加并管理多个不同的主域名。
* ☁️ **独立小黄云控制**: 精准到单个子域名，独立设定是否开启 Cloudflare 代理 (Proxied)。
* ⏳ **全自动守护**: 引导向导内嵌定时任务 (Crontab) 配置，可自动设定每 5 分钟在后台静默运行。
* 🧹 **智能日志轮转**: 自动按天切割日志，并自动清理 7 天前的历史记录，告别硬盘占满烦恼。

---

## 🚀 快速开始

### 1. 下载并运行脚本
你**不再需要**提前手动安装任何依赖。只需执行以下一条命令，下载脚本并直接运行，脚本会自动处理剩下的所有事情：

```bash
curl -# -O [https://raw.githubusercontent.com/starshine369/CF-DDNS/refs/heads/main/cloudflare_ddns.sh](https://raw.githubusercontent.com/starshine369/CF-DDNS/refs/heads/main/cloudflare_ddns.sh) && chmod +x cloudflare_ddns.sh && ./cloudflare_ddns.sh
```

*(注：运行向导后，脚本会自动将自身安全地拷贝到 `/usr/local/bin/cloudflare_ddns.sh` 以供全局调用。)*

### 2. 跟随向导完成配置
运行后，脚本会弹出直观的交互向导，按提示填写即可：

```text
╔══════════════════════════════════════════════════╗
║       Cloudflare DDNS 终极部署向导 (双栈版)      ║
╚══════════════════════════════════════════════════╝
1. 请输入Cloudflare API Token: [你的 API Token]
2. 全局TTL值 [1-86400] (默认: 60): 

▶ 正在配置第 1 个主域名：
  输入 Zone ID: [你的区域ID]
  输入该域名的备注 (如 starshine369.top): [随意备注]
  输入子域名 (多个用逗号分隔。如 nas.a.com,web.a.com): v4.a.com,v6.a.com
  对应的记录类型 (填写 A 或 AAAA。如 A,AAAA) (默认全为 A): A,AAAA
  对应的代理状态(小黄云) (如 false,true) (默认全为 false): false,true
  ✅ 第 1 个主域名配置已记录。
──────────────────────────────────────────────────
❓ 是否需要继续添加另一个主域名(Zone ID)? (默认: n) [y/n]: 

3. 日志文件路径 (默认: /root/.cloudflare_ddns/cloudflare_ddns.log): 
──────────────────────────────────────────────────
❓ 是否自动配置定时任务 (每5分钟在后台自动执行一次)? (默认: y) [y/n]: y
✅ 定时更新任务已添加 (频率: 每 5 分钟)
❓ 是否配置日志自动清理 (每天凌晨切割日志并清理7天前的记录)? (默认: n) [y/n]: y
✅ 日志清理任务已添加 (保留7天)
🎉 所有定时调度配置完毕！
```

---

## 🛠️ 常用命令

由于脚本已自动配置为全局命令，日后你可以在任何目录直接使用以下指令：

* **重新配置 (重置向导)**：如果填错了或想增加新域名，请使用此命令（⚠️ 强烈建议通过向导修改配置，避免手动破坏底层多域名数组结构）。
    ```bash
    cloudflare_ddns.sh -reconfig
    ```
* **彻底卸载**：一键清除配置文件、所有生成的日志文件以及 Crontab 中的定时任务。
    ```bash
    cloudflare_ddns.sh -delete
    ```
* **查看帮助**：
    ```bash
    cloudflare_ddns.sh -h
    ```

---

## 📊 日志与监控

脚本默认将所有运行日志保存在 `~/.cloudflare_ddns/cloudflare_ddns.log`。你可以使用以下命令进行监控：

**实时监控 DDNS 运行状态：**
```bash
tail -f ~/.cloudflare_ddns/cloudflare_ddns.log
```

**快速检索错误信息：**
```bash
grep -i "error\|fail\|not found\|无法\|❌" ~/.cloudflare_ddns/cloudflare_ddns.log
```

*(可选进阶)* **失败时发送邮件通知：**
如果你想在更新失败时收到邮件通知，可以手动编辑定时任务 (`crontab -e`)，将脚本自动生成的规则修改为如下格式：
```bash
*/5 * * * * /usr/local/bin/cloudflare_ddns.sh >> /root/.cloudflare_ddns/cloudflare_ddns.log 2>&1 || mail -s "Cloudflare DDNS Update Failed" your@email.com < /root/.cloudflare_ddns/cloudflare_ddns.log
```
*(前提：系统已配置好 `sendmail` 或 `postfix` 等邮件服务)*

---

## ⚠️ 注意事项

1.  **API Token 权限**：由于本脚本支持多主域名管理，在 Cloudflare 生成 API Token 时，请务必将权限范围（Zone Resources）设定为 **"Include - All zones"**，或手动包含所有你需要操作的具体域名，否则将提示 API 权限不足。
2.  **智能参数补齐**：在向导中输入“记录类型”和“小黄云状态”时，如果你所有的子域名都需要相同的配置（比如全是 A 记录），你只需输入一个 `A` 即可，脚本会自动为后续域名补齐。如果输入数量少于域名数量，缺少的项将默认使用 `A` 和 `false`。
3.  **找不到 IP 提示**：如果配置了 `AAAA` 记录但你的服务器并未开启 IPv6，脚本不会报错崩溃，只会跳过该条记录的更新并在日志中发出友好警告。
