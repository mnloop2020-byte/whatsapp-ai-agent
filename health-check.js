#!/usr/bin/env node

// ══════════════════════════════════════════════════════════════
//  WhatsApp AI Agent v6 — Health Check
//  شغّل هذا السكريبت قبل الربط بـ Meta للتأكد من كل شي
//  Run this before connecting to Meta to verify everything works
//
//  Usage:
//    node health-check.js
//
//  Requirements:
//    node >= 18  (uses native fetch)
// ══════════════════════════════════════════════════════════════

// ── Load .env if present ─────────────────────────────────────
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

if (existsSync('.env')) {
  const lines = readFileSync('.env', 'utf8').split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const [key, ...rest] = trimmed.split('=');
    if (key && rest.length) process.env[key.trim()] = rest.join('=').trim();
  }
  console.log('📄 Loaded .env file\n');
}

// ── Helpers ───────────────────────────────────────────────────
const PASS  = '✅';
const FAIL  = '❌';
const WARN  = '⚠️ ';
const INFO  = 'ℹ️ ';

let totalPass = 0;
let totalFail = 0;
let totalWarn = 0;

function pass(msg)  { console.log(`  ${PASS}  ${msg}`); totalPass++; }
function fail(msg)  { console.log(`  ${FAIL}  ${msg}`); totalFail++; }
function warn(msg)  { console.log(`  ${WARN} ${msg}`);  totalWarn++; }
function info(msg)  { console.log(`  ${INFO} ${msg}`); }
function section(title) {
  console.log(`\n${'─'.repeat(50)}`);
  console.log(`  ${title}`);
  console.log('─'.repeat(50));
}

// ── 1. Environment Variables ──────────────────────────────────
section('1️⃣  متغيرات البيئة | Environment Variables');

const REQUIRED_VARS = [
  { key: 'GEMINI_API_KEY',           desc: 'Google Gemini API key' },
  { key: 'WHATSAPP_ACCESS_TOKEN',    desc: 'WhatsApp access token' },
  { key: 'WHATSAPP_PHONE_NUMBER_ID', desc: 'WhatsApp phone number ID' },
  { key: 'WHATSAPP_VERIFY_TOKEN',    desc: 'Webhook verify token' },
  { key: 'WHATSAPP_APP_SECRET',      desc: 'App secret from Meta' },
  { key: 'SUPABASE_URL',             desc: 'Supabase project URL' },
  { key: 'SUPABASE_KEY',             desc: 'Supabase service_role key' },
];

const OPTIONAL_VARS = [
  { key: 'REDIS_URL',          desc: 'Upstash Redis URL (optional — fallback to static data)' },
  { key: 'REDIS_TOKEN',        desc: 'Upstash Redis token' },
  { key: 'TELEGRAM_BOT_TOKEN', desc: 'Telegram bot token (optional — for error alerts)' },
  { key: 'TELEGRAM_CHAT_ID',   desc: 'Telegram chat ID' },
  { key: 'BOT_NAME',           desc: 'Bot display name' },
  { key: 'RATE_LIMIT_PER_MIN', desc: 'Rate limit per user per minute (default: 10)' },
];

for (const v of REQUIRED_VARS) {
  const val = process.env[v.key];
  if (!val) {
    fail(`${v.key} — مفقود | missing  (${v.desc})`);
  } else if (val.includes('YOUR_') || val.includes('PLACEHOLDER')) {
    fail(`${v.key} — لم يُعبَّأ | placeholder value detected`);
  } else {
    const masked = val.slice(0, 6) + '••••••';
    pass(`${v.key} = ${masked}  (${v.desc})`);
  }
}

console.log('');
for (const v of OPTIONAL_VARS) {
  const val = process.env[v.key];
  if (!val) {
    warn(`${v.key} — غير مضبوط | not set  (${v.desc})`);
  } else {
    pass(`${v.key} ✓  (${v.desc})`);
  }
}

// ── 2. Supabase ───────────────────────────────────────────────
section('2️⃣  Supabase');

const supaUrl = process.env.SUPABASE_URL;
const supaKey = process.env.SUPABASE_KEY;

if (!supaUrl || !supaKey) {
  fail('Supabase غير مضبوط — تخطي الاختبار | not configured, skipping');
} else {
  // Check URL format
  if (!supaUrl.startsWith('https://') || !supaUrl.includes('.supabase.co')) {
    fail(`SUPABASE_URL يبدو خاطئاً | invalid format: ${supaUrl}`);
  } else {
    pass(`SUPABASE_URL format صحيح | valid`);
  }

  // Check key type
  if (supaKey.startsWith('eyJ') && supaKey.length > 100) {
    pass('SUPABASE_KEY يبدو صحيحاً | key format looks valid');
  } else {
    fail('SUPABASE_KEY يبدو خاطئاً — تأكد إنه service_role key | invalid format');
  }

  // Test connection — ping tenants table
  try {
    const res = await fetch(`${supaUrl}/rest/v1/tenants?limit=1`, {
      headers: {
        'apikey': supaKey,
        'Authorization': `Bearer ${supaKey}`
      }
    });
    if (res.ok) {
      const data = await res.json();
      pass(`اتصال Supabase ناجح | connection OK (tenants table reachable)`);
      info(`عدد الـ tenants الحالية | current tenants: ${data.length}`);
    } else if (res.status === 401) {
      fail(`Supabase رفض المفتاح (401) — تأكد إنه service_role وليس anon | unauthorized`);
    } else {
      fail(`Supabase رجع خطأ | error ${res.status}: ${await res.text()}`);
    }
  } catch (e) {
    fail(`فشل الاتصال بـ Supabase | connection failed: ${e.message}`);
  }

  // Check required tables exist
  const REQUIRED_TABLES = ['tenants', 'users', 'conversations', 'tasks', 'errors', 'tenant_stats', 'business_knowledge', 'bot_config'];
  try {
    const res = await fetch(
      `${supaUrl}/rest/v1/?apikey=${supaKey}`,
      { headers: { 'apikey': supaKey, 'Authorization': `Bearer ${supaKey}` } }
    );
    // Try each table
    let missingTables = [];
    for (const table of REQUIRED_TABLES) {
      const r = await fetch(`${supaUrl}/rest/v1/${table}?limit=0`, {
        headers: { 'apikey': supaKey, 'Authorization': `Bearer ${supaKey}` }
      });
      if (r.ok || r.status === 406) {
        // 406 = table exists but no rows match — that's fine
      } else if (r.status === 404 || r.status === 400) {
        missingTables.push(table);
      }
    }
    if (missingTables.length === 0) {
      pass(`كل الجداول موجودة | all ${REQUIRED_TABLES.length} tables exist`);
    } else {
      fail(`جداول مفقودة — شغّل SUPABASE_SCHEMA_v6.sql | missing tables: ${missingTables.join(', ')}`);
    }
  } catch(e) {
    warn(`تعذّر التحقق من الجداول | could not verify tables: ${e.message}`);
  }
}

// ── 3. Redis ──────────────────────────────────────────────────
section('3️⃣  Redis (Upstash)');

const redisUrl   = process.env.REDIS_URL;
const redisToken = process.env.REDIS_TOKEN;

if (!redisUrl || !redisToken) {
  warn('Redis غير مضبوط — البوت سيعمل بدونه لكن الـ dedup لن يستمر عند الـ restart');
  warn('Redis not configured — bot works without it but dedup resets on restart');
} else {
  try {
    const res = await fetch(`${redisUrl}/ping`, {
      headers: { Authorization: `Bearer ${redisToken}` }
    });
    const text = await res.text();
    if (res.ok && text.includes('PONG')) {
      pass('Redis متصل وشغال | connected and responding');
    } else {
      fail(`Redis رجع غير متوقع | unexpected response: ${text}`);
    }
  } catch(e) {
    fail(`فشل الاتصال بـ Redis | connection failed: ${e.message}`);
  }
}

// ── 4. Gemini API ─────────────────────────────────────────────
section('4️⃣  Google Gemini API');

const geminiKey = process.env.GEMINI_API_KEY;

if (!geminiKey) {
  fail('GEMINI_API_KEY مفقود | missing');
} else {
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: 'ping' }] }],
          generationConfig: { maxOutputTokens: 5 }
        })
      }
    );
    if (res.ok) {
      pass('Gemini API يعمل | API responding correctly');
      info('Model: gemini-2.0-flash ✓');
    } else if (res.status === 400) {
      pass('Gemini API مفتاح صحيح | valid key (400 = model reachable)');
    } else if (res.status === 403 || res.status === 401) {
      fail(`Gemini API رفض المفتاح (${res.status}) — تحقق من GEMINI_API_KEY | invalid key`);
    } else if (res.status === 429) {
      warn('Gemini API وصل الـ quota | rate limited — key is valid but quota exceeded');
    } else {
      fail(`Gemini API خطأ | error ${res.status}`);
    }
  } catch(e) {
    fail(`فشل الاتصال بـ Gemini | connection failed: ${e.message}`);
  }
}

// ── 5. WhatsApp / Meta ────────────────────────────────────────
section('5️⃣  WhatsApp Business API');

const waToken   = process.env.WHATSAPP_ACCESS_TOKEN;
const waPhoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
const waSecret  = process.env.WHATSAPP_APP_SECRET;
const waVerify  = process.env.WHATSAPP_VERIFY_TOKEN;

if (!waToken || !waPhoneId) {
  fail('WhatsApp credentials مفقودة | missing WHATSAPP_ACCESS_TOKEN or WHATSAPP_PHONE_NUMBER_ID');
} else {
  try {
    const res = await fetch(
      `https://graph.facebook.com/v18.0/${waPhoneId}?fields=display_phone_number,verified_name`,
      { headers: { Authorization: `Bearer ${waToken}` } }
    );
    if (res.ok) {
      const data = await res.json();
      pass(`WhatsApp token صحيح | valid token`);
      info(`رقم الهاتف | Phone: ${data.display_phone_number || 'N/A'}`);
      info(`اسم العمل | Business: ${data.verified_name || 'N/A'}`);
    } else if (res.status === 190) {
      fail('WhatsApp token منتهي | expired token — renew from Meta Developer Console');
    } else if (res.status === 401 || res.status === 400) {
      fail(`WhatsApp token خاطئ (${res.status}) | invalid token`);
    } else {
      warn(`WhatsApp API رجع ${res.status} — قد يكون الـ token صحيح لكن تحقق`);
    }
  } catch(e) {
    fail(`فشل التحقق من WhatsApp | check failed: ${e.message}`);
  }
}

if (!waSecret) {
  warn('WHATSAPP_APP_SECRET مفقود — الـ webhook signature verification معطّل');
} else {
  pass('WHATSAPP_APP_SECRET موجود | webhook signature verification enabled');
}

if (!waVerify) {
  fail('WHATSAPP_VERIFY_TOKEN مفقود — الـ webhook لن يتحقق من Meta | missing');
} else {
  pass(`WHATSAPP_VERIFY_TOKEN موجود | set (${waVerify.slice(0,4)}••••)`);
}

// ── 6. Telegram (optional) ────────────────────────────────────
section('6️⃣  Telegram (اختياري | optional)');

const tgToken  = process.env.TELEGRAM_BOT_TOKEN;
const tgChatId = process.env.TELEGRAM_CHAT_ID;

if (!tgToken || !tgChatId) {
  warn('Telegram غير مضبوط — تنبيهات الأخطاء معطّلة | error alerts disabled');
} else {
  try {
    const res = await fetch(`https://api.telegram.org/bot${tgToken}/getMe`);
    if (res.ok) {
      const data = await res.json();
      pass(`Telegram bot شغال | bot active: @${data.result?.username}`);
      info(`Chat ID: ${tgChatId}`);
    } else {
      fail('Telegram bot token خاطئ | invalid token');
    }
  } catch(e) {
    fail(`فشل التحقق من Telegram | check failed: ${e.message}`);
  }
}

// ── Summary ───────────────────────────────────────────────────
console.log(`\n${'═'.repeat(50)}`);
console.log('  📊 النتيجة النهائية | Summary');
console.log('═'.repeat(50));
console.log(`  ${PASS}  نجح | Passed : ${totalPass}`);
console.log(`  ${FAIL}  فشل | Failed : ${totalFail}`);
console.log(`  ${WARN} تحذير | Warned : ${totalWarn}`);
console.log('');

if (totalFail === 0 && totalWarn === 0) {
  console.log('  🎉 كل شي جاهز! يمكنك الربط بـ Meta الآن');
  console.log('  🎉 Everything looks great! Ready to connect to Meta.');
} else if (totalFail === 0) {
  console.log('  ✅ جاهز للتشغيل مع تحذيرات بسيطة');
  console.log('  ✅ Ready to run — review warnings above.');
} else {
  console.log('  ⛔ أصلح الأخطاء أعلاه قبل الربط بـ Meta');
  console.log('  ⛔ Fix the errors above before connecting to Meta.');
}

console.log('');
