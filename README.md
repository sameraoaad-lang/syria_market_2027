# سوق سوريا الشامل 2026 — المرحلة 1

## خطوات التشغيل

هذا المجلد يحتوي على كود Dart/Flutter لطبقة `lib/` فقط (بدون هياكل
`android/` و`ios/` الخاصة بمنصّات التشغيل). لتشغيل المشروع:

1. أنشئ مشروع Flutter فارغ:
   ```bash
   flutter create souq_syria
   ```
2. انسخ محتوى هذا المجلد (`lib/`, `pubspec.yaml`, `analysis_options.yaml`,
   `assets/`, `supabase/`) إلى داخل مشروعك الجديد، مع استبدال
   `pubspec.yaml` الافتراضي بالملف المرفق هنا.
3. ثبّت الحزم:
   ```bash
   flutter pub get
   ```
4. نفّذ ملف `supabase/schema.sql` داخل مشروعك على Supabase من
   قسم SQL Editor لإنشاء الجداول (`categories`, `profiles`, `ads`,
   `favorites`) وسياسات الأمان (RLS) و Bucket الصور.
5. شغّل التطبيق:
   ```bash
   flutter run
   ```

## ملاحظة هامة يجب حسمها قبل المرحلة الثانية

ورد في طلبك بريدان مختلفان للمشرف الإداري:
- في قسم "إعدادات الاتصال": `sameraoaab@gmail.com`
- في قسم "التحقق من صلاحيات الأدمن": `sameraoaad@gmail.com`

تم اعتماد الصيغة الأولى (`sameraoaab@gmail.com`) في `AppConfig.adminEmail`
وفي دالة `handle_new_user()` بملف `schema.sql`. أكّد لي البريد الصحيح
قبل المرحلة الثانية لتصحيحه إذا لزم الأمر (مكان التعديل: سطر واحد فقط
في `lib/config/app_config.dart` وسطر واحد في `supabase/schema.sql`).
