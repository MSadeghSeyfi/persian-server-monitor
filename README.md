# 🛡 ناظر امنیتی سرور لینوکس

<div dir="rtl">

ابزار **رایگان** و **متن‌باز** برای مانیتورینگ و هشدار امنیتی سرور لینوکس از طریق **بله** یا **تلگرام** — به زبان فارسی

![Version](https://img.shields.io/badge/version-1.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Language](https://img.shields.io/badge/lang-Persian-red)
![Platform](https://img.shields.io/badge/platform-Linux-orange)
![Support](https://img.shields.io/badge/alerts-Bale%20%7C%20Telegram-blueviolet)

---

## 📱 نمونه پیام‌ها

<!-- تصویر ۱: اسکرین‌شات پیام‌های دریافتی در بله را اینجا بگذارید -->
<!-- پیشنهاد: تصویری که چند پیام مختلف (تست، SSH، Fail2ban) را نشان دهد -->

![نمونه پیام‌های دریافتی](screenshots/messages.png)

---

## ✨ قابلیت‌ها

| قابلیت | توضیح |
|--------|-------|
| 🖥 هشدار CPU | اگر مصرف از حد مجاز بالاتر رفت خبر می‌دهد |
| 💾 هشدار RAM | مصرف غیرعادی حافظه را اطلاع می‌دهد |
| 📁 هشدار دیسک | پر شدن فضای ذخیره‌سازی |
| ⚙️ بررسی سرویس‌ها | nginx، fail2ban و هر سرویس دیگری |
| 🌐 بررسی سایت | اگر سایت از دسترس خارج شد فوری خبر می‌دهد |
| 🔑 ورود SSH | هر ورود به سرور + تشخیص IP ناشناس |
| 🚨 حمله SSH | Fail2ban چه IP هایی را بلاک کرد |
| 🔌 پورت جدید | اگر پورت ناشناخته‌ای باز شد هشدار می‌دهد |
| 🔒 آپدیت امنیتی | وجود به‌روزرسانی‌های امنیتی را اطلاع می‌دهد |
| 📄 تغییر فایل‌های مهم | /etc/passwd و /etc/shadow و ... |
| 📊 گزارش روزانه | هر روز صبح خلاصه کامل وضعیت سرور |

---

## 🚀 نصب سریع

```bash
git clone https://github.com/YOUR_USERNAME/server-monitor.git
cd server-monitor
chmod +x monitor.sh
cp config.conf.example config.conf
nano config.conf
bash monitor.sh test
```

---

## ⚙️ تنظیمات

فایل `config.conf` را ویرایش کنید:

```bash
# پیام‌رسان: bale یا telegram
MESSENGER="bale"

# توکن ربات (از @BotFather دریافت کنید)
BOT_TOKEN="توکن_ربات_خود_را_اینجا_بگذارید"

# شناسه چت
CHAT_ID="شناسه_چت_خود_را_اینجا_بگذارید"

# حدهای هشدار (درصد)
CPU_THRESHOLD=85
RAM_THRESHOLD=85
DISK_THRESHOLD=80

# سرویس‌های مانیتور (با کاما جدا کنید)
MONITOR_SERVICES="nginx,fail2ban,ssh"

# سایت‌های مانیتور (با کاما جدا کنید)
MONITOR_WEBSITES="https://example.com"

# IP های مورد اعتماد برای SSH
TRUSTED_IPS="1.2.3.4"
```

---

## 🤖 ساخت ربات

### در بله
۱. اپلیکیشن بله را باز کنید
۲. با `@BotFather` چت کنید
۳. دستور `/newbot` را ارسال کنید
۴. یک نام برای ربات انتخاب کنید
۵. **توکن** دریافت‌شده را در `config.conf` وارد کنید

<!-- تصویر ۲: اسکرین‌شات مراحل ساخت ربات در بله را اینجا بگذارید -->
<!-- پیشنهاد: تصویر پیام @BotFather که توکن را نشان می‌دهد (توکن را blur کنید) -->

![ساخت ربات در بله](screenshots/botfather.png)

### در تلگرام
همان مراحل بالا — فقط در تلگرام

---

## ⏰ تنظیم اجرای خودکار

```bash
crontab -e
```

```cron
# بررسی هر ۵ دقیقه
*/5 * * * * /home/ubuntu/server-monitor/monitor.sh all

# گزارش روزانه ساعت ۸ صبح
0 8 * * * /home/ubuntu/server-monitor/monitor.sh daily
```

<!-- تصویر ۳: اسکرین‌شات گزارش روزانه در بله را اینجا بگذارید -->
<!-- پیشنهاد: تصویر پیام گزارش روزانه کامل (اطلاعات حساس را blur کنید) -->

![گزارش روزانه](screenshots/daily-report.png)

---

## 📋 دستورات

```bash
bash monitor.sh test       # تست اتصال به ربات
bash monitor.sh all        # بررسی همه موارد
bash monitor.sh daily      # ارسال گزارش روزانه
bash monitor.sh cpu        # فقط CPU
bash monitor.sh ram        # فقط RAM
bash monitor.sh disk       # فقط دیسک
bash monitor.sh services   # فقط سرویس‌ها
bash monitor.sh websites   # فقط سایت‌ها
bash monitor.sh pm2        # فقط PM2
bash monitor.sh ssh        # فقط ورودهای SSH
bash monitor.sh fail2ban   # فقط Fail2ban
bash monitor.sh ports      # فقط پورت‌های باز
bash monitor.sh updates    # فقط آپدیت‌های امنیتی
bash monitor.sh files      # فقط تغییر فایل‌های مهم
```

---

## 🔔 نمونه هشدارها

<!-- تصویر ۴: اسکرین‌شات هشدار Fail2ban یا SSH را اینجا بگذارید -->
<!-- پیشنهاد: تصویر پیام "حمله SSH بلاک شد" یا "ورود SSH ناشناس" (IP را blur کنید) -->

![هشدار امنیتی](screenshots/security-alert.png)

---

## 🧪 تست‌شده روی

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Debian 11/12

---

## 📄 مجوز

این پروژه تحت مجوز [MIT](LICENSE) منتشر شده است — استفاده، تغییر و توزیع آزاد است.

---

<p align="center">ساخته شده با ❤️ برای جامعه فارسی‌زبان لینوکس</p>

</div>
