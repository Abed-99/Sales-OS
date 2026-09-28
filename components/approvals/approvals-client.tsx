"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type ApprovalRequest = {
  id: string;
  request_type: string;
  reference_type: string | null;
  reference_id: string | null;
  title: string;
  description: string | null;
  payload: Record<string, unknown>;
  status: "pending" | "approved" | "rejected" | "cancelled";
  requested_at: string;
  resolved_at: string | null;
  resolution_notes: string | null;
  requested_by: string | null;
  resolved_by: string | null;
  created_at: string;
};

export type ApprovalLookups = {
  members: Record<string, string>;
  traders: Record<string, string>;
  products: Record<string, { name: string; unit: string | null }>;
  quotes: Record<string, string>;
};

type PayloadItem = {
  product_id?: string;
  quantity?: number | string;
  sale_unit_price?: number | string;
};

type GuardDetail = {
  product_id?: string;
  reference_cost?: number | string | null;
  minimum_sale_price?: number | string | null;
};

type Filter = "all" | "pending" | "approved" | "rejected";

function num(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function friendlyError(raw: string | undefined) {
  const message = (raw ?? "").toLowerCase();
  if (message.includes("not allowed")) return "ما عندك صلاحية توافق أو ترفض.";
  if (message.includes("pending approval request not found"))
    return "هالطلب انحسم من قبل (حدا تاني وافق أو رفض). حدّث الصفحة.";
  if (message.includes("quote has expired")) return "عرض السعر انتهت صلاحيته. لازم يتعمل عرض جديد.";
  if (message.includes("no longer accepted") || message.includes("must be accepted"))
    return "عرض السعر ما عاد مقبول (انلغى أو تعدّل).";
  if (message.includes("already converted")) return "عرض السعر تحوّل لطلبية من قبل.";
  if (message.includes("does not match quote") || message.includes("trader mismatch"))
    return "عرض السعر تعدّل بعد ما انطلبت الموافقة. لازم ينطلب من جديد.";
  if (message.includes("invalid trader")) return "الزبون موقوف أو محذوف.";
  if (message.includes("inactive product") || message.includes("invalid approved order item"))
    return "في صنف بالطلب صار موقوف أو محذوف.";
  if (message.includes("finance period") && message.includes("closed"))
    return "الشهر المحاسبي مقفل.";
  return "تعذر تنفيذ القرار. حاول مرة تانية.";
}

function formatDate(value: string, withTime = false) {
  return new Intl.DateTimeFormat("ar-SY", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}),
  }).format(new Date(value));
}

export function ApprovalsClient({
  companyId,
  currency,
  requests,
  lookups,
  canResolve,
}: {
  companyId: string;
  currency: string;
  requests: ApprovalRequest[];
  lookups: ApprovalLookups;
  canResolve: boolean;
}) {
  const [supabase] = useState(() => createClient());

  const router = useRouter();

  const [filter, setFilter] = useState<Filter>("pending");

  const [selected, setSelected] = useState<ApprovalRequest | null>(null);

  const [notes, setNotes] = useState("");

  const [saving, setSaving] = useState(false);

  const [message, setMessage] = useState("");

  const [search, setSearch] = useState("");

  const money = (value: number) =>
    `${value.toLocaleString("en-US", { maximumFractionDigits: 2 })} ${currency}`;

  const traderName = (request: ApprovalRequest) =>
    lookups.traders[String(request.payload?.trader_id ?? "")] ?? null;

  const personName = (id: string | null) => (id ? (lookups.members[id] ?? "—") : "—");

  function referenceLabel(request: ApprovalRequest) {
    const quoteId = String(request.payload?.source_quote_id ?? "");
    if (request.payload?.order_id) return "طلبية انعملت";
    if (quoteId && lookups.quotes[quoteId]) return `عرض سعر ${lookups.quotes[quoteId]}`;
    if (request.reference_type === "sales_order_request") return "طلبية جديدة";
    if (request.reference_type === "sales_quote") return "عرض سعر";
    return request.reference_type || "—";
  }

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();

    return requests.filter((request) => {
      if (filter !== "all" && request.status !== filter) return false;
      if (!term) return true;

      const haystack = [
        request.title,
        request.description,
        lookups.traders[String(request.payload?.trader_id ?? "")],
        lookups.quotes[String(request.payload?.source_quote_id ?? "")],
        request.requested_by ? lookups.members[request.requested_by] : "",
        ...(Array.isArray(request.payload?.items)
          ? (request.payload.items as PayloadItem[]).map(
              (item) => lookups.products[String(item?.product_id ?? "")]?.name,
            )
          : []),
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return haystack.includes(term);
    });
  }, [requests, filter, search, lookups]);

  const pending = requests.filter((request) => request.status === "pending").length;

  const approved = requests.filter((request) => request.status === "approved").length;

  const rejected = requests.filter((request) => request.status === "rejected").length;

  async function resolve(decision: "approved" | "rejected") {
    if (!selected) {
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc("resolve_approval_request", {
      target_company: companyId,

      target_request: selected.id,

      target_decision: decision,

      target_notes: notes.trim() || null,
    });

    setSaving(false);

    if (error) {
      setMessage(friendlyError(error.message));
      return;
    }

    setSelected(null);
    setNotes("");

    router.refresh();
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">الموافقات</span>

          <h2>مركز الموافقات</h2>

          <p className="muted">أي عملية حساسة تحتاج اعتماد تظهر هون.</p>
        </div>
      </div>

      <section className="statsGrid">
        <Mini title="بانتظار الموافقة" value={String(pending)} />

        <Mini title="تمت الموافقة" value={String(approved)} />

        <Mini title="مرفوض" value={String(rejected)} />

        <Mini title="إجمالي الطلبات" value={String(requests.length)} />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        <FilterButton active={filter === "pending"} onClick={() => setFilter("pending")}>
          معلقة
        </FilterButton>

        <FilterButton active={filter === "approved"} onClick={() => setFilter("approved")}>
          مقبولة
        </FilterButton>

        <FilterButton active={filter === "rejected"} onClick={() => setFilter("rejected")}>
          مرفوضة
        </FilterButton>

        <FilterButton active={filter === "all"} onClick={() => setFilter("all")}>
          الكل
        </FilterButton>

        <div className="searchBox" style={{ flex: 1, minWidth: 220 }}>
          <Icons.search size={14} />

          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="بحث: الزبون، الصنف، رقم العرض، مين طلب..."
            aria-label="بحث بالموافقات"
          />
        </div>
      </div>

      {message && (
        <div
          className="toastError"
          style={{
            marginTop: 12,
          }}
        >
          {message}
        </div>
      )}

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        {!filtered.length ? (
          <div className="empty">
            <Icons.check size={30} />

            <h3>ما في طلبات هون</h3>

            <p>ما في موافقات مطابقة للحالة المختارة.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الطلب</th>
                  <th>الزبون</th>
                  <th>المرجع</th>
                  <th>طلبها</th>
                  <th>التاريخ</th>
                  <th>الحالة</th>
                  <th />
                </tr>
              </thead>

              <tbody>
                {filtered.map((request) => (
                  <tr key={request.id}>
                    <td>
                      <strong>{typeLabel(request.request_type)}</strong>

                      <div className="muted">{request.title}</div>
                    </td>

                    <td>{traderName(request) ?? "—"}</td>

                    <td>{referenceLabel(request)}</td>

                    <td>{personName(request.requested_by)}</td>

                    <td>{formatDate(request.requested_at)}</td>

                    <td>
                      <span
                        className={`chip ${
                          request.status === "pending"
                            ? "orange"
                            : request.status === "approved"
                              ? "green"
                              : "gray"
                        }`}
                      >
                        {statusLabel(request.status)}
                      </span>
                    </td>

                    <td>
                      <button
                        type="button"
                        className="softButton"
                        onClick={() => {
                          setSelected(request);

                          setNotes(request.resolution_notes || "");

                          setMessage("");
                        }}
                      >
                        عرض
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {selected && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">{typeLabel(selected.request_type)}</span>

                <h2>{traderName(selected) ?? selected.title}</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setSelected(null)}>
                ×
              </button>
            </div>

            <div className="formGrid">
              <Info label="الحالة" value={statusLabel(selected.status)} />

              <Info label="المرجع" value={referenceLabel(selected)} />

              <Info label="طلبها" value={personName(selected.requested_by)} />

              <Info label="تاريخ الطلب" value={formatDate(selected.requested_at, true)} />

              {selected.resolved_at ? (
                <Info
                  label={selected.status === "approved" ? "وافق عليها" : "رفضها"}
                  value={`${personName(selected.resolved_by)} • ${formatDate(selected.resolved_at, true)}`}
                />
              ) : null}
            </div>

            {typeof selected.payload?.order_id === "string" ? (
              <Link
                className="softButton"
                style={{ marginTop: 12 }}
                href={`/orders?order=${selected.payload.order_id}`}
              >
                فتح الطلبية
              </Link>
            ) : null}

            {selected.description && (
              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                {selected.description}
              </div>
            )}

            <PayloadDetails request={selected} lookups={lookups} money={money} />

            {selected.status === "pending" && canResolve && (
              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>ملاحظات القرار</span>

                <textarea
                  rows={3}
                  value={notes}
                  onChange={(event) => setNotes(event.target.value)}
                />
              </label>
            )}

            {selected.resolution_notes && selected.status !== "pending" && (
              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                <strong>ملاحظات القرار</strong>

                <p>{selected.resolution_notes}</p>
              </div>
            )}

            {message && <div className="toastError">{message}</div>}

            <div className="modalActions">
              <button type="button" className="softButton" onClick={() => setSelected(null)}>
                إغلاق
              </button>

              {selected.status === "pending" && canResolve && (
                <>
                  <button
                    type="button"
                    className="dangerButton"
                    disabled={saving}
                    onClick={() => void resolve("rejected")}
                  >
                    رفض
                  </button>

                  <button
                    type="button"
                    className="primaryButton"
                    disabled={saving}
                    onClick={() => void resolve("approved")}
                  >
                    موافقة
                  </button>
                </>
              )}
            </div>
          </section>
        </div>
      )}
    </div>
  );
}

function PayloadDetails({
  request,
  lookups,
  money,
}: {
  request: ApprovalRequest;
  lookups: ApprovalLookups;
  money: (value: number) => string;
}) {
  const items = Array.isArray(request.payload?.items)
    ? (request.payload.items as PayloadItem[])
    : [];

  if (!items.length) return null;

  const guards = new Map(
    (Array.isArray(request.payload?.price_guard_details)
      ? (request.payload.price_guard_details as GuardDetail[])
      : []
    ).map((guard) => [String(guard.product_id ?? ""), guard]),
  );

  let total = 0;
  let costTotal = 0;

  const rows = items.map((item, index) => {
    const productId = String(item.product_id ?? "");
    const product = lookups.products[productId];
    const quantity = num(item.quantity);
    const price = num(item.sale_unit_price);
    const guard = guards.get(productId);
    const cost = guard?.reference_cost == null ? null : num(guard.reference_cost);
    const minimum = guard?.minimum_sale_price == null ? null : num(guard.minimum_sale_price);

    total += quantity * price;
    // بس الأصناف اللي عم تنباع بخسارة، ما منخلّي ربح صنف يغطّي خسارة صنف تاني.
    if (cost != null && price < cost) costTotal += quantity * (cost - price);

    return (
      <tr key={`${productId}-${index}`}>
        <td>
          <strong>{product?.name ?? "صنف"}</strong>
          {guard ? <div className="chip orange">تحت الحد</div> : null}
        </td>
        <td>
          {quantity.toLocaleString("en-US", { maximumFractionDigits: 3 })} {product?.unit ?? ""}
        </td>
        <td>{money(price)}</td>
        <td>{cost == null ? "—" : money(cost)}</td>
        <td>{minimum == null ? "—" : money(minimum)}</td>
        <td>{money(quantity * price)}</td>
      </tr>
    );
  });

  const notes = typeof request.payload?.notes === "string" ? request.payload.notes : "";

  return (
    <div className="panel" style={{ marginTop: 14 }}>
      <div className="tableWrap">
        <table className="dataTable">
          <thead>
            <tr>
              <th>الصنف</th>
              <th>الكمية</th>
              <th>السعر المطلوب</th>
              <th>الكلفة</th>
              <th>أقل سعر مسموح</th>
              <th>المجموع</th>
            </tr>
          </thead>
          <tbody>{rows}</tbody>
        </table>
      </div>

      <div className="panelPad">
        <strong>مجموع الطلب: {money(total)}</strong>
        {costTotal > 0 ? (
          <div className="muted" style={{ color: "var(--danger)" }}>
            خسارة الأصناف المباعة تحت الكلفة: {money(costTotal)}
          </div>
        ) : null}
        {notes ? <p className="muted">ملاحظات: {notes}</p> : null}
      </div>
    </div>
  );
}

function FilterButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button type="button" className={active ? "primaryButton" : "softButton"} onClick={onClick}>
      {children}
    </button>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="field">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>

      <div className="statValue">{value}</div>
    </div>
  );
}

function statusLabel(status: ApprovalRequest["status"]) {
  if (status === "pending") {
    return "بانتظار الموافقة";
  }

  if (status === "approved") {
    return "موافق عليه";
  }

  if (status === "rejected") {
    return "مرفوض";
  }

  return "ملغى";
}

function typeLabel(type: string) {
  const labels: Record<string, string> = {
    discount: "خصم استثنائي",
    below_cost_sale: "بيع تحت التكلفة",
    below_cost_order: "طلب بيع تحت التكلفة",
    inventory_adjustment: "تسوية مخزون",
    expense: "مصروف",
    purchase: "شراء",
    payment: "دفعة",
    manual_journal: "قيد يدوي",
  };

  return labels[type] || type;
}
