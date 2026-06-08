#!/bin/bash
# ============================================================
#   نصب‌کننده خودکار ناظر امنیتی سرور
#   استفاده: sudo bash install.sh
# ============================================================
set -e

DIR="$(dirname "$(realpath "$0")")"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${GREEN}🛡 نصب ناظر امنیتی سرور${NC}"
echo "════════════════════════════════"

# ۱. ساخت فایل تنظیمات
if [ ! -f "$DIR/config.conf" ]; then
    cp "$DIR/config.conf.example" "$DIR/config.conf"
    echo -e "${YELLOW}⚙️  فایل config.conf ساخته شد — حتماً ویرایشش کنید!${NC}"
fi

chmod +x "$DIR/monitor.sh" "$DIR/bot.sh"

# ۲. تنظیم cron
echo -e "${GREEN}⏰ تنظیم زمان‌بندی خودکار...${NC}"
( crontab -l 2>/dev/null | grep -v "server-monitor"
  echo "*/5 * * * * $DIR/monitor.sh all >> $DIR/monitor.log 2>&1  # server-monitor"
  echo "0 8 * * * $DIR/monitor.sh daily >> $DIR/monitor.log 2>&1  # server-monitor"
) | crontab -

# ۳. نصب سرویس بات تعاملی
echo -e "${GREEN}🤖 نصب سرویس بات تعاملی...${NC}"
USER_NAME=$(whoami)
sudo tee /etc/systemd/system/server-monitor-bot.service > /dev/null << EOF
[Unit]
Description=Server Monitor Interactive Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
ExecStart=/bin/bash ${DIR}/bot.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable server-monitor-bot

echo "════════════════════════════════"
echo -e "${GREEN}✅ نصب کامل شد!${NC}"
echo ""
echo "قدم‌های بعدی:"
echo "  ۱. تنظیمات را ویرایش کنید:  nano $DIR/config.conf"
echo "  ۲. تست اتصال:                bash $DIR/monitor.sh test"
echo "  ۳. اجرای بات:                sudo systemctl start server-monitor-bot"
