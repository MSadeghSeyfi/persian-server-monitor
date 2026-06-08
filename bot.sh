#!/bin/bash
# ============================================================
#   بات تعاملی ناظر امنیتی سرور
#   به دستورهای کاربر مجاز پاسخ می‌دهد (long polling)
#   نسخه: 1.1.0
# ============================================================

CONFIG_FILE="$(dirname "$(realpath "$0")")/config.conf"
source "$CONFIG_FILE"
MONITOR="$(dirname "$(realpath "$0")")/monitor.sh"

if [ "$MESSENGER" = "bale" ]; then
    API="https://tapi.bale.ai/bot${BOT_TOKEN}"
else
    API="https://api.telegram.org/bot${BOT_TOKEN}"
fi

# ─── ارسال پاسخ (به چت مشخص) ─────────────────────────────
reply() {
    curl -s -X POST "${API}/sendMessage" \
        -d chat_id="$1" \
        --data-urlencode text="$2" \
        -d parse_mode="HTML" --noproxy "*" --max-time 10 >/dev/null 2>&1
}

# ─── آیا این شناسه چت مجاز است؟ ──────────────────────────
is_authorized() {
    local CID="$1"
    IFS=',' read -ra IDS <<< "$CHAT_ID"
    for ID in "${IDS[@]}"; do
        [ "$(echo "$ID" | xargs)" = "$CID" ] && return 0
    done
    return 1
}

# ─── منوی راهنما ──────────────────────────────────────────
help_text() {
    echo "🤖 <b>ناظر امنیتی سرور</b>
━━━━━━━━━━━━━━━━━━
دستورهای موجود:

📊 /status — وضعیت کلی سرور
⚙️ /services — وضعیت سرویس‌ها
🌐 /site — وضعیت سایت‌ها
🛡 /security — خلاصه امنیتی
🔑 /logins — آخرین ورودهای SSH
🚫 /bans — IP های بلاک‌شده
🔌 /ports — پورت‌های باز
🔒 /updates — آپدیت‌های امنیتی
📈 /top — پروسه‌های پرمصرف
📋 /report — گزارش کامل روزانه
❓ /help — این راهنما
━━━━━━━━━━━━━━━━━━"
}

# ─── وضعیت کلی ────────────────────────────────────────────
cmd_status() {
    local CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    local RT=$(free -m | awk '/Mem:/{print $2}')
    local RU=$(free -m | awk '/Mem:/{print $3}')
    local RP=$((RU * 100 / RT))
    local DISK=$(df -h / | tail -1 | awk '{print $5}')
    local UP=$(uptime -p | sed 's/up //')
    local LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local CONN=$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l)
    echo "📊 <b>وضعیت سرور</b>
━━━━━━━━━━━━━━━━━━
🖥 سرور: $(hostname)
⏱ آپتایم: ${UP}
🕐 $(date '+%Y-%m-%d %H:%M:%S')

• CPU: ${CPU:-?}%
• RAM: ${RP}% (${RU}/${RT} MB)
• دیسک: ${DISK}
• Load: ${LOAD}
• اتصالات فعال: ${CONN}
━━━━━━━━━━━━━━━━━━"
}

# ─── سرویس‌ها ─────────────────────────────────────────────
cmd_services() {
    local OUT="⚙️ <b>وضعیت سرویس‌ها</b>
━━━━━━━━━━━━━━━━━━
"
    IFS=',' read -ra S <<< "$MONITOR_SERVICES"
    for SVC in "${S[@]}"; do
        SVC=$(echo "$SVC" | xargs)
        systemctl is-active --quiet "$SVC" 2>/dev/null \
            && OUT="${OUT}✅ ${SVC}
" || OUT="${OUT}❌ ${SVC}
"
    done
    echo "$OUT"
}

# ─── سایت‌ها ──────────────────────────────────────────────
cmd_site() {
    [ -z "$MONITOR_WEBSITES" ] && { echo "🌐 سایتی تنظیم نشده است."; return; }
    local OUT="🌐 <b>وضعیت سایت‌ها</b>
━━━━━━━━━━━━━━━━━━
"
    IFS=',' read -ra SITES <<< "$MONITOR_WEBSITES"
    for SITE in "${SITES[@]}"; do
        SITE=$(echo "$SITE" | xargs); [ -z "$SITE" ] && continue
        local CODE=$(curl -s -o /dev/null -w "%{http_code}" --noproxy "*" --max-time 15 -L "$SITE" 2>/dev/null)
        [[ "$CODE" =~ ^[23] ]] \
            && OUT="${OUT}✅ ${SITE} (${CODE})
" || OUT="${OUT}❌ ${SITE} (${CODE})
"
    done
    echo "$OUT"
}

# ─── خلاصه امنیتی ─────────────────────────────────────────
cmd_security() {
    local BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    local TOTAL=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    local FAILED=$(sudo grep -c "Failed password" /var/log/auth.log 2>/dev/null)
    local UPDATES=$(apt-get -s upgrade 2>/dev/null | grep "^Inst" | grep -ci security)
    local FW=$(sudo ufw status 2>/dev/null | grep -c "ALLOW")
    echo "🛡 <b>خلاصه امنیتی</b>
━━━━━━━━━━━━━━━━━━
🚫 IP بلاک‌شده الان: ${BANNED:-0}
📊 کل بلاک‌ها: ${TOTAL:-0}
⚠️ تلاش‌های ناموفق ورود: ${FAILED:-0}
🔒 آپدیت‌های امنیتی: ${UPDATES:-0}
🔥 قوانین فایروال فعال: ${FW:-0}
━━━━━━━━━━━━━━━━━━"
}

# ─── ورودهای SSH ──────────────────────────────────────────
cmd_logins() {
    local OUT="🔑 <b>آخرین ورودهای SSH</b>
━━━━━━━━━━━━━━━━━━
<code>"
    OUT="${OUT}$(last -n 5 -a 2>/dev/null | head -5 | awk '{print $1, $3, $4, $5, $6}')"
    echo "${OUT}</code>"
}

# ─── IP های بلاک‌شده ──────────────────────────────────────
cmd_bans() {
    local IPS=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Banned IP" | cut -d: -f2 | xargs)
    echo "🚫 <b>IP های بلاک‌شده</b>
━━━━━━━━━━━━━━━━━━
<code>${IPS:-هیچ}</code>"
}

# ─── پورت‌های باز ─────────────────────────────────────────
cmd_ports() {
    local P=$(ss -tlnp 2>/dev/null | awk 'NR>1{print $4}' | sort -u | tr '\n' ' ')
    echo "🔌 <b>پورت‌های در حال شنود</b>
━━━━━━━━━━━━━━━━━━
<code>${P}</code>"
}

# ─── آپدیت‌های امنیتی ─────────────────────────────────────
cmd_updates() {
    local N=$(apt-get -s upgrade 2>/dev/null | grep "^Inst" | grep -ci security)
    echo "🔒 <b>آپدیت‌های امنیتی</b>
━━━━━━━━━━━━━━━━━━
📦 تعداد: ${N}
$([ "$N" -gt 0 ] && echo '💡 نصب: <code>sudo apt-get upgrade -y</code>' || echo '✅ سیستم به‌روز است')"
}

# ─── پروسه‌های پرمصرف ─────────────────────────────────────
cmd_top() {
    local OUT="📈 <b>پروسه‌های پرمصرف CPU</b>
━━━━━━━━━━━━━━━━━━
<code>"
    OUT="${OUT}$(ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {printf "%s%% %s\n", $3, $11}')"
    echo "${OUT}</code>"
}

# ─── پردازش دستور (به چت درخواست‌کننده پاسخ می‌دهد) ──────
handle() {
    local CMD="$1"
    local TO="$2"
    case "$CMD" in
        /start|/help)  reply "$TO" "$(help_text)" ;;
        /status)       reply "$TO" "$(cmd_status)" ;;
        /services)     reply "$TO" "$(cmd_services)" ;;
        /site)         reply "$TO" "$(cmd_site)" ;;
        /security)     reply "$TO" "$(cmd_security)" ;;
        /logins)       reply "$TO" "$(cmd_logins)" ;;
        /bans)         reply "$TO" "$(cmd_bans)" ;;
        /ports)        reply "$TO" "$(cmd_ports)" ;;
        /updates)      reply "$TO" "$(cmd_updates)" ;;
        /top)          reply "$TO" "$(cmd_top)" ;;
        /report)       "$MONITOR" daily ;;
        *)             reply "$TO" "❓ دستور ناشناخته. /help را بزنید." ;;
    esac
}

# ─── حلقه اصلی (long polling) ─────────────────────────────
echo "بات ناظر امنیتی شروع شد. در انتظار دستورها..."
OFFSET=0
while true; do
    RESP=$(curl -s --noproxy "*" --max-time 60 "${API}/getUpdates?offset=${OFFSET}&timeout=50" 2>/dev/null)
    [ -z "$RESP" ] && { sleep 2; continue; }

    # پردازش با python: خروجی هر خط = update_id<TAB>chat_id<TAB>text
    PARSED=$(echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for u in d.get('result', []):
        m = u.get('message', {})
        cid = m.get('chat', {}).get('id', '')
        txt = (m.get('text', '') or '').strip()
        print(f\"{u['update_id']}\t{cid}\t{txt}\")
except: pass
" 2>/dev/null)

    while IFS=$'\t' read -r UPD_ID CID TEXT; do
        [ -z "$UPD_ID" ] && continue
        OFFSET=$((UPD_ID + 1))
        # امنیت: فقط به کاربران مجاز (در لیست CHAT_ID) پاسخ بده
        is_authorized "$CID" || continue
        # فقط دستورهایی که با / شروع می‌شوند — پاسخ به همان چت
        [[ "$TEXT" == /* ]] && handle "$TEXT" "$CID"
    done <<< "$PARSED"
done
