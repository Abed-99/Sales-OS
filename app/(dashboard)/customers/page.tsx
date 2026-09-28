import { CustomersClient } from "@/components/customers/customers-client";
import { Icons } from "@/components/icons";
import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";
import { hasPermission } from "@/lib/permissions";
import { normalizeAnyPhone } from "@/lib/phone";
import { createClient } from "@/lib/supabase/server";

type TraderStatus = "new" | "contacted" | "interested" | "customer" | "inactive";

const validStatuses = new Set<TraderStatus>([
  "new",
  "contacted",
  "interested",
  "customer",
  "inactive",
]);

function firstParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

function cleanSearch(value: string) {
  return value
    .replace(/[(),"'\\%_]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 100);
}

export default async function CustomersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const context = await getCurrentContext();
  const params = await searchParams;

  const canView = hasPermission(context.permissions, "traders.view", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar
          title="العملاء"
          subtitle="قاعدة العملاء والتواصل والمتابعة"
          companyName={context.companyName}
        />

        <div className="page">
          <section className="panel panelPad">
            <div className="empty">
              <Icons.shield size={32} />
              <h3>لا تملك صلاحية عرض العملاء</h3>
              <p>تواصل مع مالك الشركة أو مدير الصلاحيات إذا كنت تحتاج إلى الوصول لهذه الصفحة.</p>
            </div>
          </section>
        </div>
      </>
    );
  }

  const canViewBalance = hasPermission(
    context.permissions,
    "traders.view_balance",
    context.isOwner,
  );

  const search = cleanSearch(firstParam(params.q));

  const rawStatus = firstParam(params.status);

  const status: TraderStatus | "all" = validStatuses.has(rawStatus as TraderStatus)
    ? (rawStatus as TraderStatus)
    : "all";

  const requestedPage = Math.max(1, Number.parseInt(firstParam(params.page), 10) || 1);

  const pageSize = 50;
  const from = (requestedPage - 1) * pageSize;
  const to = from + pageSize - 1;

  const supabase = await createClient();

  let tradersQuery = supabase
    .from("traders")
    .select(
      "id,name,contact_name,phone,whatsapp,area,address,latitude,longitude,status,notes,whatsapp_marketing_opt_in,credit_limit,payment_terms_days,price_level_id,created_at,updated_at",
      {
        count: "exact",
      },
    )
    .eq("company_id", context.companyId)
    .order("created_at", {
      ascending: false,
    })
    .range(from, to);

  if (status !== "all") {
    tradersQuery = tradersQuery.eq("status", status);
  }

  // البحث بكل شي: الاسم، الشخص المسؤول، الهاتف، المنطقة، العنوان، الملاحظات.
  if (search) {
    const pattern = `%${search}%`;

    const conditions = [
      `name.ilike.${pattern}`,
      `contact_name.ilike.${pattern}`,
      `phone.ilike.${pattern}`,
      `whatsapp.ilike.${pattern}`,
      `area.ilike.${pattern}`,
      `address.ilike.${pattern}`,
      `notes.ilike.${pattern}`,
    ];

    // الأرقام محفوظة بصيغة +963...، فإذا كتب 0944... منبحث كمان بالصيغة المحفوظة.
    const phone = normalizeAnyPhone(search);
    if (phone) {
      conditions.push(`phone.eq.${phone}`, `whatsapp.eq.${phone}`);
    } else {
      const digits = search.replace(/\D/g, "");
      if (digits.length >= 4 && digits.startsWith("0")) {
        conditions.push(`phone.ilike.%${digits.slice(1)}%`, `whatsapp.ilike.%${digits.slice(1)}%`);
      }
    }

    tradersQuery = tradersQuery.or(conditions.join(","));
  }

  const [tradersResult, allResult, customerResult, interestedResult, newResult] = await Promise.all(
    [
      tradersQuery,

      supabase
        .from("traders")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq("company_id", context.companyId),

      supabase
        .from("traders")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq("company_id", context.companyId)
        .eq("status", "customer"),

      supabase
        .from("traders")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq("company_id", context.companyId)
        .eq("status", "interested"),

      supabase
        .from("traders")
        .select("id", {
          count: "exact",
          head: true,
        })
        .eq("company_id", context.companyId)
        .eq("status", "new"),
    ],
  );

  const hasStatsError =
    Boolean(allResult.error) ||
    Boolean(customerResult.error) ||
    Boolean(interestedResult.error) ||
    Boolean(newResult.error);

  const totalCount = tradersResult.count ?? 0;

  const { data: priceLevels } = await supabase
    .from("price_levels")
    .select("id,name,active")
    .eq("company_id", context.companyId)
    .order("sort_order")
    .order("name");

  return (
    <>
      <Topbar
        title="العملاء"
        subtitle="قاعدة العملاء، التواصل، الزيارات والمتابعة"
        companyName={context.companyName}
      />

      <CustomersClient
        companyId={context.companyId}
        currency={context.currency}
        initialTraders={tradersResult.data ?? []}
        initialError={tradersResult.error ? "تعذر تحميل العملاء. حاول تحديث الصفحة." : null}
        stats={
          hasStatsError
            ? null
            : {
                all: allResult.count ?? 0,

                customers: customerResult.count ?? 0,

                interested: interestedResult.count ?? 0,

                new: newResult.count ?? 0,
              }
        }
        totalCount={totalCount}
        page={requestedPage}
        pageSize={pageSize}
        searchQuery={search}
        statusFilter={status}
        canCreate={hasPermission(context.permissions, "traders.create", context.isOwner)}
        canUpdate={hasPermission(context.permissions, "traders.update", context.isOwner)}
        canArchive={hasPermission(context.permissions, "traders.archive", context.isOwner)}
        canViewMap={hasPermission(context.permissions, "map.view", context.isOwner)}
        canViewBalance={canViewBalance}
        canManageCredit={hasPermission(context.permissions, "traders.manage_credit", context.isOwner)}
        priceLevels={priceLevels ?? []}
      />
    </>
  );
}
