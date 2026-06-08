#!/bin/bash
# ============================================================
#   ناظر امنیتی سرور - Server Security Monitor
#   نسخه: 1.1.0
#   پشتیبانی: تلگرام و بله
#   GitHub: github.com/YOUR_USERNAME/server-monitor
#   مجوز: MIT
# ============================================================

CONFIG_FILE="$(dirname "$(realpath "$0")")/config.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "خطا: فایل config.conf پیدا نشد. از config.conf.example کپی کنید."
    exit 1
fi
source "$CONFIG_FILE"

# ─── ارسال پیام ───────────────────────────────────────────
send_message() {
    local MESSAGE="$1"
    if [ "$MESSENGER" = "bale" ]; then
        API_URL="https://tapi.bale.ai/bot${BOT_TOKEN}/sendMessage"
    else
        API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    fi
    # ارسال به همه شناسه‌های چت (با کاما جدا شده)
    IFS=',' read -ra IDS <<< "$CHAT_ID"
    for ID in "${IDS[@]}"; do
        ID=$(echo "$ID" | xargs)
        [ -z "$ID" ] && continue
        curl -s -X POST "$API_URL" \
            -d chat_id="$ID" \
            --data-urlencode text="$MESSAGE" \
            -d parse_mode="HTML" \
            --noproxy "*" \
            --max-time 10 > /dev/null 2>&1
    done
}

# ─── بررسی CPU ────────────────────────────────────────────
check_cpu() {
    local CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    if [ "${CPU:-0}" -ge "${CPU_THRESHOLD:-85}" ] 2>/dev/null; then
        send_message "⚠️ <b>هشدار مصرف CPU</b>

🖥 مصرف فعلی: <b>${CPU}%</b>
📊 حد مجاز: ${CPU_THRESHOLD}%
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)"
    fi
}

# ─── بررسی RAM ────────────────────────────────────────────
check_ram() {
    local RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
    local RAM_USED=$(free -m | awk '/Mem:/{print $3}')
    local RAM_PCT=$((RAM_USED * 100 / RAM_TOTAL))
    if [ "$RAM_PCT" -ge "${RAM_THRESHOLD:-85}" ]; then
        send_message "⚠️ <b>هشدار مصرف RAM</b>

💾 مصرف فعلی: <b>${RAM_PCT}%</b>
📊 استفاده شده: ${RAM_USED}MB از ${RAM_TOTAL}MB
📊 حد مجاز: ${RAM_THRESHOLD}%
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)"
    fi
}

# ─── بررسی دیسک ───────────────────────────────────────────
check_disk() {
    while IFS= read -r LINE; do
        local PCT=$(echo "$LINE" | awk '{print $5}' | tr -d '%')
        local MOUNT=$(echo "$LINE" | awk '{print $6}')
        if [ "${PCT:-0}" -ge "${DISK_THRESHOLD:-80}" ] 2>/dev/null; then
            send_message "💾 <b>هشدار پر شدن دیسک</b>

📁 پارتیشن: <b>${MOUNT}</b>
📊 پر شده: <b>${PCT}%</b>
📊 حد مجاز: ${DISK_THRESHOLD}%
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)"
        fi
    done < <(df -h | grep -vE 'Filesystem|tmpfs|udev')
}

# ─── بررسی سرویس‌ها ───────────────────────────────────────
check_services() {
    IFS=',' read -ra SERVICES <<< "$MONITOR_SERVICES"
    for SERVICE in "${SERVICES[@]}"; do
        SERVICE=$(echo "$SERVICE" | xargs)
        if ! systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
            send_message "🔴 <b>سرویس از کار افتاد!</b>

⚙️ سرویس: <b>${SERVICE}</b>
❌ وضعیت: متوقف شده
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)

💡 برای راه‌اندازی مجدد:
<code>sudo systemctl restart ${SERVICE}</code>"
        fi
    done
}

# ─── بررسی وضعیت سایت ────────────────────────────────────
# بررسی خارجی یک آدرس (با دور زدن پروکسی) - کد HTTP را برمی‌گرداند
http_check_external() {
    curl -s -o /dev/null -w "%{http_code}" --noproxy "*" --max-time 15 \
        -A "ServerMonitor/1.1" -L "$1" 2>/dev/null
}

# بررسی محلی اپلیکیشن از طریق nginx (با Host header) - سلامت واقعی اپ
http_check_local() {
    local HOST=$(echo "$1" | sed -E 's#^https?://##; s#/.*$##')
    curl -s -o /dev/null -w "%{http_code}" --noproxy "*" --max-time 10 \
        -H "Host: ${HOST}" "http://127.0.0.1${LOCAL_HEALTH_PATH:-/}" 2>/dev/null
}

# آیا کد HTTP سالم است؟ (2xx یا 3xx)
is_healthy() { [[ "$1" =~ ^[23] ]]; }

check_websites() {
    [ -z "$MONITOR_WEBSITES" ] && return
    IFS=',' read -ra SITES <<< "$MONITOR_WEBSITES"
    for SITE in "${SITES[@]}"; do
        SITE=$(echo "$SITE" | xargs)
        [ -z "$SITE" ] && continue

        local CODE=$(http_check_external "$SITE")
        # اگر اولین چک خراب بود، یک بار دیگر تلاش کن (جلوگیری از هشدار اشتباه گذرا)
        if ! is_healthy "$CODE"; then
            sleep 2
            CODE=$(http_check_external "$SITE")
        fi

        # وضعیت جدید: up یا down
        local STATE="up"; is_healthy "$CODE" || STATE="down"

        local LOG_FILE="/tmp/site_check_$(echo "$SITE" | md5sum | cut -c1-8).txt"
        local PREV_STATE="up"
        [ -f "$LOG_FILE" ] && PREV_STATE=$(cat "$LOG_FILE")
        echo "$STATE" > "$LOG_FILE"

        # فقط وقتی وضعیت تغییر کرد پیام بده
        [ "$STATE" = "$PREV_STATE" ] && continue

        if [ "$STATE" = "down" ]; then
            # تشخیص اینکه مشکل از اپلیکیشن است یا از CDN/شبکه بیرونی
            local LOCAL_CODE=$(http_check_local "$SITE")
            local DIAGNOSIS
            if is_healthy "$LOCAL_CODE"; then
                DIAGNOSIS="🟡 اپلیکیشن روی سرور <b>سالم</b> است (کد محلی: ${LOCAL_CODE})
ولی از بیرون در دسترس نیست — احتمالاً مشکل از CDN، DNS یا شبکه است."
            else
                DIAGNOSIS="🔴 اپلیکیشن روی سرور هم <b>پاسخ نمی‌دهد</b> (کد محلی: ${LOCAL_CODE})
احتمالاً nginx یا Next.js خوابیده است."
            fi
            send_message "🔴 <b>سایت از دسترس خارج شد!</b>

🌐 آدرس: <b>${SITE}</b>
📊 کد HTTP بیرونی: <b>${CODE}</b>
${DIAGNOSIS}
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)"
        else
            send_message "✅ <b>سایت بازگشت آنلاین</b>

🌐 آدرس: <b>${SITE}</b>
📊 کد HTTP: ${CODE}
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')"
        fi
    done
}

# ─── بررسی PM2 ────────────────────────────────────────────
check_pm2() {
    command -v pm2 &>/dev/null || return
    local STOPPED=$(pm2 jlist 2>/dev/null | python3 -c "
import sys, json
try:
    apps = json.load(sys.stdin)
    stopped = [a['name'] for a in apps if a.get('pm2_env',{}).get('status') != 'online']
    print(','.join(stopped) if stopped else '')
except: pass
" 2>/dev/null)
    if [ -n "$STOPPED" ]; then
        send_message "🔴 <b>پروسه PM2 متوقف شد!</b>

⚙️ پروسه: <b>${STOPPED}</b>
❌ وضعیت: آفلاین
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)

💡 برای راه‌اندازی مجدد:
<code>pm2 restart ${STOPPED}</code>"
    fi
}

# ─── بررسی ورودهای SSH ────────────────────────────────────
check_ssh_login() {
    local LOG_FILE="/tmp/last_ssh_check.txt"
    local LAST=$(last -n 1 ubuntu 2>/dev/null | head -1)
    local CURRENT=$(echo "$LAST" | md5sum)
    local PREVIOUS=""
    [ -f "$LOG_FILE" ] && PREVIOUS=$(cat "$LOG_FILE")
    if [ "$CURRENT" != "$PREVIOUS" ] && [ -n "$LAST" ]; then
        echo "$CURRENT" > "$LOG_FILE"
        local IP=$(echo "$LAST" | awk '{print $3}')
        local TIME=$(echo "$LAST" | awk '{print $5,$6,$7,$8}')
        local TRUSTED=false
        IFS=',' read -ra IPS <<< "$TRUSTED_IPS"
        for TIP in "${IPS[@]}"; do
            [ "$(echo "$TIP" | xargs)" = "$IP" ] && TRUSTED=true
        done
        send_message "🔑 <b>ورود SSH به سرور</b>

👤 کاربر: ubuntu
🌐 آدرس IP: <b>${IP}</b>
🕐 زمان: ${TIME}
🖥 سرور: $(hostname)
$($TRUSTED && echo '✅ IP مورد اعتماد' || echo '⚠️ <b>IP ناشناس - بررسی کنید!</b>')"
    fi
}

# ─── بررسی Fail2ban ───────────────────────────────────────
check_fail2ban() {
    command -v fail2ban-client &>/dev/null || return
    local LOG_FILE="/tmp/last_fail2ban_count.txt"
    local CURRENT=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    local PREVIOUS=0
    [ -f "$LOG_FILE" ] && PREVIOUS=$(cat "$LOG_FILE")
    if [ -n "$CURRENT" ] && [ "$CURRENT" -gt "$PREVIOUS" ] 2>/dev/null; then
        echo "$CURRENT" > "$LOG_FILE"
        local NEW=$(( CURRENT - PREVIOUS ))
        local IPS=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Banned IP" | cut -d: -f2 | xargs)
        send_message "🚨 <b>حمله SSH بلاک شد</b>

🛡 ${NEW} IP جدید توسط Fail2ban بلاک شد
🌐 IP های بلاک شده:
<code>${IPS}</code>
📊 کل بلاک‌ها: ${CURRENT}
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)"
    fi
}

# ─── بررسی پورت‌های باز جدید ──────────────────────────────
check_open_ports() {
    local LOG_FILE="/tmp/last_open_ports.txt"
    local CURRENT=$(ss -tlnp 2>/dev/null | awk 'NR>1{print $4}' | sort)
    if [ ! -f "$LOG_FILE" ]; then
        echo "$CURRENT" > "$LOG_FILE"
        return
    fi
    local PREVIOUS=$(cat "$LOG_FILE")
    local NEW_PORTS=$(comm -13 <(echo "$PREVIOUS") <(echo "$CURRENT") | grep -v '^$')
    if [ -n "$NEW_PORTS" ]; then
        echo "$CURRENT" > "$LOG_FILE"
        send_message "⚠️ <b>پورت جدید باز شد!</b>

🔌 پورت‌های جدید:
<code>${NEW_PORTS}</code>
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)

💡 اگر این پورت‌ها را نمی‌شناسید، بررسی کنید!"
    fi
}

# ─── بررسی آپدیت‌های امنیتی ──────────────────────────────
check_security_updates() {
    command -v apt-get &>/dev/null || return
    local LOG_FILE="/tmp/last_security_updates.txt"
    local UPDATES=$(apt-get -s upgrade 2>/dev/null | grep "^Inst" | grep -i security | wc -l)
    local PREVIOUS=0
    [ -f "$LOG_FILE" ] && PREVIOUS=$(cat "$LOG_FILE")
    echo "$UPDATES" > "$LOG_FILE"
    if [ "$UPDATES" -gt 0 ] && [ "$UPDATES" != "$PREVIOUS" ] 2>/dev/null; then
        send_message "🔒 <b>آپدیت‌های امنیتی موجود</b>

📦 تعداد: <b>${UPDATES} آپدیت امنیتی</b>
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)

💡 برای نصب:
<code>sudo apt-get upgrade -y</code>"
    fi
}

# ─── بررسی تغییر فایل‌های مهم ────────────────────────────
check_critical_files() {
    local LOG_FILE="/tmp/last_file_hashes.txt"
    local CRITICAL_FILES="/etc/passwd /etc/shadow /etc/ssh/sshd_config /etc/sudoers"
    local CURRENT_HASHES=$(md5sum $CRITICAL_FILES 2>/dev/null)
    if [ ! -f "$LOG_FILE" ]; then
        echo "$CURRENT_HASHES" > "$LOG_FILE"
        return
    fi
    local CHANGED=$(diff <(cat "$LOG_FILE") <(echo "$CURRENT_HASHES") | grep "^>" | awk '{print $3}')
    if [ -n "$CHANGED" ]; then
        echo "$CURRENT_HASHES" > "$LOG_FILE"
        send_message "🚨 <b>فایل مهم سیستمی تغییر کرد!</b>

📄 فایل(ها):
<code>${CHANGED}</code>
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
🖥 سرور: $(hostname)

⚠️ <b>اگر این تغییر را انجام نداده‌اید، سرور را بررسی کنید!</b>"
    fi
}

# ─── گزارش روزانه ─────────────────────────────────────────
daily_report() {
    local CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    local RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
    local RAM_USED=$(free -m | awk '/Mem:/{print $3}')
    local RAM_PCT=$((RAM_USED * 100 / RAM_TOTAL))
    local DISK=$(df -h / | tail -1 | awk '{print $5}')
    local UPTIME=$(uptime -p | sed 's/up //')
    local BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    local LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local SEC_UPDATES=$(apt-get -s upgrade 2>/dev/null | grep "^Inst" | grep -i security | wc -l)

    local SVC_STATUS=""
    IFS=',' read -ra SERVICES <<< "$MONITOR_SERVICES"
    for S in "${SERVICES[@]}"; do
        S=$(echo "$S" | xargs)
        systemctl is-active --quiet "$S" 2>/dev/null \
            && SVC_STATUS="${SVC_STATUS}✅ ${S}\n" \
            || SVC_STATUS="${SVC_STATUS}❌ ${S}\n"
    done

    local SITE_STATUS=""
    if [ -n "$MONITOR_WEBSITES" ]; then
        IFS=',' read -ra SITES <<< "$MONITOR_WEBSITES"
        for SITE in "${SITES[@]}"; do
            SITE=$(echo "$SITE" | xargs)
            [ -z "$SITE" ] && continue
            local CODE=$(http_check_external "$SITE")
            is_healthy "$CODE" \
                && SITE_STATUS="${SITE_STATUS}✅ ${SITE} (${CODE})\n" \
                || SITE_STATUS="${SITE_STATUS}❌ ${SITE} (${CODE})\n"
        done
    fi

    send_message "📊 <b>گزارش روزانه سرور</b>
━━━━━━━━━━━━━━━━━━
🖥 <b>سرور:</b> $(hostname)
🕐 <b>زمان:</b> $(date '+%Y-%m-%d %H:%M')
⏱ <b>آپتایم:</b> ${UPTIME}

<b>📈 منابع:</b>
• CPU: ${CPU:-?}%
• RAM: ${RAM_PCT}% (${RAM_USED}/${RAM_TOTAL} MB)
• دیسک: ${DISK}
• Load: ${LOAD}

<b>⚙️ سرویس‌ها:</b>
$(echo -e "$SVC_STATUS")
<b>🌐 سایت‌ها:</b>
$(echo -e "${SITE_STATUS:-بدون تنظیم\n}")
<b>🛡 امنیت:</b>
• Fail2ban بلاک‌ها: ${BANNED:-0}
• آپدیت‌های امنیتی: ${SEC_UPDATES}
━━━━━━━━━━━━━━━━━━"
}

# ─── اجرای اصلی ───────────────────────────────────────────
case "${1:-all}" in
    cpu)            check_cpu ;;
    ram)            check_ram ;;
    disk)           check_disk ;;
    services)       check_services ;;
    websites)       check_websites ;;
    pm2)            check_pm2 ;;
    ssh)            check_ssh_login ;;
    fail2ban)       check_fail2ban ;;
    ports)          check_open_ports ;;
    updates)        check_security_updates ;;
    files)          check_critical_files ;;
    daily)          daily_report ;;
    test)
        send_message "✅ <b>اتصال برقرار است</b>

🤖 ناظر امنیتی سرور فعال شد
🖥 سرور: $(hostname)
🕐 زمان: $(date '+%Y-%m-%d %H:%M:%S')
📡 پیام‌رسان: ${MESSENGER}"
        echo "پیام تست ارسال شد ✅"
        ;;
    all)
        check_cpu
        check_ram
        check_disk
        check_services
        check_websites
        check_pm2
        check_ssh_login
        check_fail2ban
        check_open_ports
        check_critical_files
        ;;
    *)
        echo "استفاده: $0 {all|cpu|ram|disk|services|websites|pm2|ssh|fail2ban|ports|updates|files|daily|test}"
        exit 1
        ;;
esac
