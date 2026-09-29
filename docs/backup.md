# النسخ الاحتياطي

كل يوم الساعة 3 الفجر (توقيت دمشق) GitHub بياخد نسخة كاملة من قاعدة البيانات، بيشفّرها،
وبيحفظها 90 يوم. الملف: `.github/workflows/db-backup.yml`.

## التجهيز (مرة وحدة)

1. بـ Supabase: **Connect → Session pooler**، انسخ رابط الاتصال (بيبلّش بـ `postgresql://`)
   وحط كلمة سر قاعدة البيانات مكان `[YOUR-PASSWORD]`.
2. بـ GitHub: المستودع ← **Settings → Secrets and variables → Actions → New repository secret**:
   - `SUPABASE_DB_URL` = الرابط من الخطوة 1.
   - `BACKUP_PASSPHRASE` = كلمة سر طويلة من عندك. **احفظها بمكان آمن**: بدونها النسخ ما بتنفتح.
3. جرّب: **Actions → نسخة احتياطية يومية → Run workflow**. لازم تخلص بعلامة ✓ خضرا.

## تنزيل نسخة

**Actions →** افتح أي تشغيل ← تحت **Artifacts** نزّل `sales-os-backup-…`.
جوّاته ملف `sales-os-backup_YYYY-MM-DD_HHMM.tar.gz.gpg`.

## الاسترجاع

```bash
# 1) فك التشفير (بيطلب كلمة السر BACKUP_PASSPHRASE)
gpg -d sales-os-backup_2026-09-29_0300.tar.gz.gpg > backup.tar.gz
tar -xzf backup.tar.gz

# 2) قاعدة فاضية (مشروع Supabase جديد أو محلي): أول شي البنية
npx supabase db push            # أو: npx supabase db reset (محلي)

# 3) البيانات
pg_restore --data-only --no-owner -d "$DB_URL" auth_*.dump
pg_restore --data-only --no-owner --disable-triggers -d "$DB_URL" public_*.dump
pg_restore --data-only --no-owner -d "$DB_URL" storage_*.dump
```

- `public_*.dump`: كل جداول النظام (الأصناف، الفواتير، الحسابات، القيود...).
- `auth_*.dump`: حسابات الدخول، مشان الموظفين يفوتوا بنفس كلمات سرهن.
- `storage_*.dump`: سجلّات صور الأصناف. الصور نفسها محفوظة بمخزن Supabase.

> الأحسن تجرّب استرجاع نسخة على مشروع تجربة مرة كل كم شهر، لتتأكد إنو كلشي ماشي.
