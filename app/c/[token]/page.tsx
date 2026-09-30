import type { Metadata } from "next";

import { PublicCatalog, type PublicCatalogData } from "@/components/catalog/public-catalog";
import styles from "@/components/catalog/public-catalog.module.css";
import { createClient } from "@/lib/supabase/server";

// صفحة الكتالوج العامة: بتنفتح بدون تسجيل دخول. كل شي بيجي من get_public_catalog حسب إعدادات الرابط.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "كتالوج البضاعة",
  robots: { index: false, follow: false },
};

export default async function CatalogPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const supabase = await createClient();
  const { data } = await supabase.rpc("get_public_catalog", { target_token: token });

  if (!data) {
    return (
      <main className={styles.page}>
        <div className={styles.closed}>
          <h1>الرابط مش شغّال</h1>
          <p>يمكن انتهى أو انوقف. اطلب رابط جديد من الشركة.</p>
        </div>
      </main>
    );
  }

  return <PublicCatalog token={token} data={data as PublicCatalogData} />;
}
