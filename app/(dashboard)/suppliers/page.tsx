import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { SuppliersClient } from "@/components/suppliers/suppliers-client";
import { createClient } from "@/lib/supabase/server";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";

export default async function SuppliersPage() {
  const context = await getCurrentContext();
  const can = (code: string) => hasPermission(context.permissions, code, context.isOwner);

  if (!can("suppliers.view")) {
    return (
      <>
        <Topbar title="الموردون" subtitle="بيانات الموردين وأسعار الشراء" companyName={context.companyName} />
        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield size={32} />
              <h3>لا تملك صلاحية عرض الموردين</h3>
            </div>
          </section>
        </div>
      </>
    );
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("suppliers")
    .select("id,name,contact_name,phone,whatsapp,address,notes,active,payment_terms_days,created_at")
    .eq("company_id", context.companyId)
    .order("created_at", { ascending: false });

  return (
    <>
      <Topbar
        title="الموردون"
        subtitle="بيانات الموردين، التواصل وأسعار الشراء"
        companyName={context.companyName}
      />
      <SuppliersClient
        companyId={context.companyId}
        initialRows={data || []}
        initialError={error ? "تعذر تحميل الموردين. حاول تحديث الصفحة." : null}
        canCreate={can("suppliers.create")}
        canUpdate={can("suppliers.update")}
        canArchive={can("suppliers.archive")}
      />
    </>
  );
}
