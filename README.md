# 🤖 WhatsApp AI Agent — v6 (Multi-Tenant)

وكيل ذكاء اصطناعي احترافي على واتساب | A professional AI agent for WhatsApp  
مبني بـ n8n + Google Gemini + Supabase | Built with n8n + Google Gemini + Supabase

---

## ✨ الميزات | Features

- 🏢 دعم عدة عملاء من نفس البوت | Multi-Tenant support
- 🧠 ذاكرة محادثة مستمرة | Persistent conversation memory (Redis + Supabase)
- 🎙️ تفريغ الرسائل الصوتية | Voice message transcription (OpenAI Whisper)
- 🖼️ تحليل الصور | Image analysis (Gemini Vision)
- ⏰ تذكيرات ذكية بالعربية | Smart reminders with Arabic date support
- 📊 لوحة تحكم حية | Live dashboard
- 🔒 حماية Webhook | Webhook signature verification
- 🛡️ حماية من السبام | Rate limiting & deduplication
- 🚨 تنبيهات أخطاء على Telegram | Error alerts on Telegram

---

## 🛠️ التقنيات المستخدمة | Tech Stack

| التقنية | الاستخدام | Usage |
|---|---|---|
| n8n | محرك الأتمتة | Automation engine |
| Google Gemini | الذكاء الاصطناعي | AI brain |
| Supabase | قاعدة البيانات | Database |
| WhatsApp Business API | قناة التواصل | Communication channel |
| Redis (Upstash) | الذاكرة القصيرة | Short-term memory |
| OpenAI Whisper | تفريغ الصوت | Voice transcription |

---

## 📁 ملفات المشروع | Project Files

| الملف | الوصف | Description |
|---|---|---|
| `whatsapp-ai-agent-v6.json` | الـ workflow الرئيسي | Main workflow (27 nodes) |
| `task-scheduler-v5.json` | جدولة التذكيرات | Task scheduler & daily report |
| `SUPABASE_SCHEMA_v6.sql` | قاعدة البيانات | Full database schema |
| `dashboard.html` | لوحة التحكم | Live dashboard |
| `WhatsApp_AI_Agent_README.docx` | الشرح الكامل | Full setup guide |
| `test-data.json` | بيانات الاختبار | Test payloads & checklist |
| `health-check.js` | فحص الاتصالات | Verify all connections before launch |

---

## 🚀 طريقة التشغيل | How to Run

للشرح الكامل خطوة بخطوة افتح ملف | For the full step-by-step guide open:  
📄 **WhatsApp_AI_Agent_README.docx**

### الخطوات السريعة | Quick Steps

1. شغّل ملف SQL على Supabase | Run SQL schema on Supabase
2. استورد الـ workflows في n8n | Import workflows into n8n
3. أضف متغيرات البيئة | Add environment variables
4. **شغّل `node health-check.js` وتأكد كل شي ✅**
5. اربط الـ Webhook على Meta | Connect Webhook on Meta
6. افتح dashboard.html في المتصفح | Open dashboard.html in browser

---

## ⚙️ متغيرات البيئة المطلوبة | Required Environment Variables

| المتغير | الوصف | Description |
|---|---|---|
| `GEMINI_API_KEY` | مفتاح Gemini | Google Gemini API key |
| `WHATSAPP_ACCESS_TOKEN` | توكن واتساب | WhatsApp access token |
| `WHATSAPP_PHONE_NUMBER_ID` | معرّف الرقم | Phone number ID |
| `WHATSAPP_VERIFY_TOKEN` | رمز التحقق | Webhook verify token |
| `WHATSAPP_APP_SECRET` | سر التطبيق | App secret from Meta |
| `SUPABASE_URL` | رابط Supabase | Supabase project URL |
| `SUPABASE_KEY` | مفتاح Supabase | Supabase service role key |

---

## 🧪 الاختبار قبل الإطلاق | Testing Before Launch

افتح `test-data.json` — فيه 10 حالات اختبار تغطي كل السيناريوهات:

| الاختبار | ما يختبره |
|---|---|
| T01 | رد على التحية |
| T02 | سؤال عن منتج من business_knowledge |
| T03-T05 | تحليل التواريخ العربية |
| T06 | رسالة غير واضحة |
| T07 | منع الرسائل المكررة (dedup) |
| T08 | رفض التوقيع الخاطئ (security) |
| T09 | عزل الـ tenants |
| T10 | Webhook verification handshake |

في n8n: افتح الـ workflow ← اضغط **Test Workflow** ← الصق أي payload من الملف.

---



| المشكلة | الحل | Fix |
|---|---|---|
| البوت لا يستقبل رسائل | تحقق من VERIFY_TOKEN | Check VERIFY_TOKEN matches Meta |
| Gemini لا يرد | تحقق من GEMINI_API_KEY | Verify GEMINI_API_KEY is valid |
| التذكيرات لا تُرسل | فعّل الـ scheduler | Activate the scheduler workflow |
| Dashboard فارغ | استخدم service_role key | Use service_role key not anon key |

---

## 📋 التغييرات | Changelog

### v6
- ✅ RLS policies مكتملة لكل الجداول | Full RLS policies for all tables
- ✅ عمود `phone_number` في جدول users | `phone_number` column added to users
- ✅ جدول `bot_config` لتثبيت Gemini model | `bot_config` table to pin Gemini model
- ✅ Retry logic في task scheduler | Retry logic in task scheduler
- ✅ Dedup يستخدم Redis بدل static data | Dedup now uses Redis (persists across restarts)
- ✅ Gemini model يُقرأ من bot_config per tenant | Gemini model read from bot_config per tenant
- ✅ phone_number يُحفظ في Supabase log | phone_number saved in Supabase log

---

## 📄 الترخيص | License

MIT License

Copyright (c) 2026 mnloop2020-byte

---

*بُني هذا المشروع بـ n8n · Google Gemini · Supabase · WhatsApp Business API*  
*Built with n8n · Google Gemini · Supabase · WhatsApp Business API*
