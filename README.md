CF-DDNS 配置向导

所有配置将存储在: /root/.cloudflare_ddns

提示：括号内为默认值，直接按回车使用默认设置

──────────────────────────────────────────────────

请输入Cloudflare API Token: 你的API Token

请输入Zone ID: 你的域名区域ID

请输入要更新的域名(多个域名用逗号分隔，如 a.com,b.com): 你的域名

记录类型 [A/AAAA] (默认: A，可直接按回车):

TTL值 [1-86400] (默认: 60，可直接按回车):

是否开启代理(小黄云) (多个用逗号分隔，如 false,true) (默认: false):

日志文件路径 (默认: /root/.cloudflare_ddns/cloudflare_ddns.log，可直接按回车):

──────────────────────────────────────────────────

✅ 配置已保存到: /root/.cloudflare_ddns/config

📝 日志将记录到: /root/.cloudflare_ddns/cloudflare_ddns.log

下次运行脚本将自动使用这些配置

══════════════════════════════════════════════════

1.安装必要依赖
确保已安装 jq 工具：

Debian/Ubuntu
```bash
sudo apt update && sudo apt install -y jq curl
```

2.获取 DDNS 脚本并执行
```bash
curl -# -o /usr/local/bin/cloudflare_ddns.sh https://raw.githubusercontent.com/starshine369/CF-DDNS/refs/heads/main/cloudflare_ddns.sh && chmod +x /usr/local/bin/cloudflare_ddns.sh && /usr/local/bin/cloudflare_ddns.sh
```

保存脚本路径为 /usr/local/bin/cloudflare_ddns.sh

3.设置 crontab 定时任务
编辑当前用户的 crontab：
```bash
crontab -e
```

添加以下内容（每5分钟运行一次并记录日志）（shell版）：

每5分钟运行一次DDNS脚本并记录日志
```bash
*/5 * * * * /usr/local/bin/cloudflare_ddns.sh >> /root/.cloudflare_ddns/cloudflare_ddns.log 2>&1
```

可选：每天凌晨清理日志（保留7天日志）
```bash
0 0 * * * find /root/.cloudflare_ddns/cloudflare_ddns.log -mtime +7 -delete
```

4.监控日志文件
你可以使用以下命令监控日志：

实时查看日志
```bash
tail -f /root/.cloudflare_ddns/cloudflare_ddns.log
```

查看最后20条日志
```bash
tail -n 20 /root/.cloudflare_ddns/cloudflare_ddns.log
```

搜索错误
```bash
grep -i "error\|fail\|not found\|无法" /root/.cloudflare_ddns/cloudflare_ddns.log
```

5.添加邮件通知（可选）
如果你想在更新失败时收到邮件通知，可以修改 crontab：

每5分钟运行一次，失败时发送邮件
```bash
*/5 * * * * /usr/local/bin/cloudflare_ddns.sh >> /root/.cloudflare_ddns/cloudflare_ddns.log 2>&1 || mail -s "Cloudflare DDNS Update Failed" your@email.com < /root/.cloudflare_ddns/cloudflare_ddns.log
```
确保系统已配置邮件服务（如 sendmail 或 postfix）。

🛠️ 进阶：如何手动修改多域名与小黄云配置
如果你后续想要增加域名，无需重新配置，直接编辑配置文件即可：
```bash
nano /root/.cloudflare_ddns/config
```

内容示例：
```bash
RECORD_NAME='ddns1.example.com,ddns2.example.com'
PROXIED='false,true'
```
注：PROXIED 的值必须与 RECORD_NAME 里的域名一一对应。上面的例子代表 ddns1 关闭小黄云，ddns2 开启小黄云。

注意事项

权限问题：确保脚本和日志文件有正确的读写权限

API Token权限：确认API Token有足够的权限（Zone DNS Edit）

多域名对应关系：在使用多域名时，请确保 PROXIED 参数中的 true/false 数量与域名的数量一致且用逗号隔开

日志轮转：对于长期运行，考虑设置日志轮转

IP获取服务：如果某些IP服务被屏蔽，可以编辑 get_ip() 函数尝试其他服务
