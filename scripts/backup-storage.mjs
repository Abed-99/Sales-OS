// بينزّل كل صور الأصناف (bucket product-images) لمجلد، للنسخة الاحتياطية اليومية.
// الاستعمال: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/backup-storage.mjs out/storage
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { createClient } = require("@supabase/supabase-js");

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const target = process.argv[2] || "out/storage";
const bucket = "product-images";

if (!url || !key) {
  console.error("لازم SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const storage = createClient(url, key, { auth: { persistSession: false } }).storage.from(bucket);

// المجلدات ما إلها id؛ الملفات إلها.
async function walk(prefix) {
  const files = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await storage.list(prefix, { limit: 1000, offset });
    if (error) throw error;
    for (const item of data) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id) files.push(path);
      else files.push(...(await walk(path)));
    }
    if (data.length < 1000) return files;
  }
}

const files = await walk("");
let bytes = 0;
for (const path of files) {
  const { data, error } = await storage.download(path);
  if (error) throw new Error(`${path}: ${error.message}`);
  const buffer = Buffer.from(await data.arrayBuffer());
  const out = join(target, bucket, path);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, buffer);
  bytes += buffer.length;
}
console.log(`${files.length} صورة (${(bytes / 1024 / 1024).toFixed(1)} MB)`);
