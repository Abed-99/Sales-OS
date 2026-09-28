"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type DeliveryQueueItem = {
  id: string;
  product_id: string;
  quantity: number;
  sale_unit_price: number;
  product_name: string;
  sku: string | null;
  unit: string | null;
  delivered_quantity: number;
  active_quantity: number;
  remaining_quantity: number;
};

export type DeliveryTrader = {
  id: string;
  name: string;
  area: string | null;
  address: string | null;
  phone: string | null;
  whatsapp: string | null;
  latitude: number | null;
  longitude: number | null;
};

export type DeliveryQueueRow = {
  id: string;
  order_number: string | null;

  status: "ready" | "out_for_delivery";

  payment_status: string;

  total: number;
  created_at: string;
  ordered_at: string | null;

  trader: DeliveryTrader | null;

  items: DeliveryQueueItem[];
};

export type DeliveryStats = {
  readyCount: number;
  roadCount: number;
  roadUnits: number;
  remainingUnits: number;
};

type DeliveryStatusFilter = "all" | "ready" | "out_for_delivery";

type Notice = {
  type: "success" | "error";

  text: string;
};

/** 15 بدل 15.000 */
function qty(value: unknown) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 3 }).format(numeric(value));
}

function numeric(value: unknown) {
  const result = Number(value ?? 0);

  return Number.isFinite(result) ? result : 0;
}

function money(value: number, currency: string) {
  return `${new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(numeric(value))} ${currency}`;
}

function formatDateTime(value: string | null) {
  if (!value) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("ar", {
    timeZone: "Asia/Damascus",

    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function friendlyError(
  error: {
    code?: string;
    message?: string;
  } | null,
  action: "start" | "complete" | "fail",
) {
  const raw = error?.message ?? "";

  const message = raw.toLowerCase();

  if (
    error?.code === "42501" ||
    message.includes("not allowed") ||
    message.includes("permission")
  ) {
    return "ما عندك صلاحية لتنفيذ هذه العملية.";
  }

  if (message.includes("order not found")) {
    return "الطلبية غير موجودة أو لم تعد متاحة.";
  }

  if (message.includes("not ready for delivery")) {
    return "الطلبية لم تعد جاهزة للتوصيل.";
  }

  if (message.includes("active delivery") || message.includes("already has an active delivery")) {
    return "يوجد توصيل نشط لهذه الطلبية حالياً.";
  }

  if (
    message.includes("exceeds remaining") ||
    message.includes("exceeds remaining order quantity")
  ) {
    return "إحدى الكميات أكبر من الكمية المتبقية للتوصيل.";
  }

  if (
    message.includes("not fully reserved") ||
    message.includes("reserved stock is missing") ||
    message.includes("could not allocate reserved stock")
  ) {
    return "المخزون المحجوز لم يعد كافياً لهذه التسليمة. حدّث الصفحة وراجع المخزون.";
  }

  if (message.includes("not currently out for delivery")) {
    return "الطلبية لم تعد بحالة التوصيل.";
  }

  if (message.includes("active delivery not found")) {
    return "لم تعد هناك تسليمة نشطة لهذه الطلبية.";
  }

  if (message.includes("failure reason required")) {
    return "سبب فشل التوصيل مطلوب.";
  }

  if (message.includes("cannot be failed")) {
    return "لا يمكن تسجيل فشل هذه التسليمة لأنها سُلّمت أو تمت فوترتها.";
  }

  if (action === "start") {
    return "تعذر تجهيز التسليمة. راجع الكميات وحاول مرة ثانية.";
  }

  if (action === "complete") {
    return "تعذر تأكيد التسليم.";
  }

  return "تعذر تسجيل فشل التوصيل.";
}

export function DeliveriesClient({
  companyId,
  currency,
  initialRows,
  initialStats,
  totalCount,
  page,
  pageSize,
  searchQuery,
  statusFilter,
  canUpdate,
  canViewMap,
  initialError,
}: {
  companyId: string;
  currency: string;

  initialRows: DeliveryQueueRow[];

  initialStats: DeliveryStats;

  totalCount: number;
  page: number;
  pageSize: number;

  searchQuery: string;

  statusFilter: DeliveryStatusFilter;

  canUpdate: boolean;
  canViewMap: boolean;

  initialError: string | null;
}) {
  const [supabase] = useState(() => createClient());

  const router = useRouter();

  const searchParams = useSearchParams();

  const [rows, setRows] = useState(initialRows);

  const [notice, setNotice] = useState<Notice | null>(
    initialError
      ? {
          type: "error",

          text: initialError,
        }
      : null,
  );

  const [search, setSearch] = useState(searchQuery);

  const [filter, setFilter] = useState<DeliveryStatusFilter>(statusFilter);

  const [deliveryTarget, setDeliveryTarget] = useState<DeliveryQueueRow | null>(null);

  const [quantities, setQuantities] = useState<Record<string, string>>({});

  const [deliveryMessage, setDeliveryMessage] = useState("");

  const [completeTarget, setCompleteTarget] = useState<DeliveryQueueRow | null>(null);

  const [completeNotes, setCompleteNotes] = useState("");

  const [completeMessage, setCompleteMessage] = useState("");

  const [failTarget, setFailTarget] = useState<DeliveryQueueRow | null>(null);

  const [failReason, setFailReason] = useState("");

  const [failMessage, setFailMessage] = useState("");

  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    setRows(initialRows);
  }, [initialRows]);

  useEffect(() => {
    setSearch(searchQuery);

    setFilter(statusFilter);
  }, [searchQuery, statusFilter]);

  useEffect(() => {
    if (initialError) {
      setNotice({
        type: "error",
        text: initialError,
      });
    }
  }, [initialError]);

  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));

  function navigate(nextSearch: string, nextFilter: DeliveryStatusFilter, nextPage = 1) {
    const params = new URLSearchParams(searchParams.toString());

    const clean = nextSearch.trim();

    if (clean) {
      params.set("q", clean);
    } else {
      params.delete("q");
    }

    if (nextFilter !== "all") {
      params.set("status", nextFilter);
    } else {
      params.delete("status");
    }

    if (nextPage > 1) {
      params.set("page", String(nextPage));
    } else {
      params.delete("page");
    }

    const query = params.toString();

    router.push(query ? `/deliveries?${query}` : "/deliveries");
  }

  function openDelivery(order: DeliveryQueueRow) {
    if (!canUpdate || order.status !== "ready") {
      return;
    }

    const next: Record<string, string> = {};

    for (const item of order.items) {
      const remaining = numeric(item.remaining_quantity);

      next[item.id] = remaining > 0 ? String(remaining) : "0";
    }

    setQuantities(next);

    setDeliveryMessage("");

    setDeliveryTarget(order);
  }

  function fillAll() {
    if (!deliveryTarget) {
      return;
    }

    const next: Record<string, string> = {};

    for (const item of deliveryTarget.items) {
      next[item.id] = String(numeric(item.remaining_quantity));
    }

    setQuantities(next);
  }

  async function saveDelivery(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!deliveryTarget || !canUpdate) {
      return;
    }

    setDeliveryMessage("");

    const payload: Array<{
      sales_order_item_id: string;

      quantity: number;
    }> = [];

    for (const item of deliveryTarget.items) {
      const quantity = numeric(quantities[item.id]);

      const remaining = numeric(item.remaining_quantity);

      if (quantity < 0) {
        setDeliveryMessage("كمية التوصيل لا يمكن أن تكون سالبة.");
        return;
      }

      if (quantity > remaining + 0.0005) {
        setDeliveryMessage(`كمية ${item.product_name} أكبر من المتبقي.`);
        return;
      }

      if (quantity > 0) {
        payload.push({
          sales_order_item_id: item.id,

          quantity: Number(quantity.toFixed(3)),
        });
      }
    }

    if (!payload.length) {
      setDeliveryMessage("حدد كمية واحدة على الأقل للتوصيل.");
      return;
    }

    setBusyId(deliveryTarget.id);

    try {
      const { error } = await supabase.rpc("create_order_delivery", {
        target_company: companyId,

        target_order: deliveryTarget.id,

        items_payload: payload,
      });

      if (error) {
        setDeliveryMessage(friendlyError(error, "start"));
        return;
      }

      setRows((current) =>
        current.map((order) => {
          if (order.id !== deliveryTarget.id) {
            return order;
          }

          const byItem = new Map(payload.map((item) => [item.sales_order_item_id, item.quantity]));

          return {
            ...order,

            status: "out_for_delivery",

            items: order.items.map((item) => {
              const sent = byItem.get(item.id) ?? 0;

              return {
                ...item,

                active_quantity: numeric(item.active_quantity) + sent,

                remaining_quantity: Math.max(numeric(item.remaining_quantity) - sent, 0),
              };
            }),
          };
        }),
      );

      setDeliveryTarget(null);

      setNotice({
        type: "success",

        text: "تم تجهيز التسليمة وتحويل الطلبية إلى بالطريق.",
      });

      router.refresh();
    } finally {
      setBusyId(null);
    }
  }

  function openComplete(order: DeliveryQueueRow) {
    if (!canUpdate || order.status !== "out_for_delivery") {
      return;
    }

    setCompleteTarget(order);

    setCompleteNotes("");

    setCompleteMessage("");
  }

  async function saveComplete(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!completeTarget || !canUpdate) {
      return;
    }

    setBusyId(completeTarget.id);

    setCompleteMessage("");

    try {
      const { error } = await supabase.rpc("complete_order_delivery", {
        target_company: companyId,

        target_order: completeTarget.id,

        target_notes: completeNotes.trim() || null,
      });

      if (error) {
        setCompleteMessage(friendlyError(error, "complete"));
        return;
      }

      setCompleteTarget(null);

      setNotice({
        type: "success",

        text: "تم تأكيد وصول التسليمة، خصم المخزون وإنشاء فاتورة البيع.",
      });

      router.refresh();
    } finally {
      setBusyId(null);
    }
  }

  function openFail(order: DeliveryQueueRow) {
    if (!canUpdate || order.status !== "out_for_delivery") {
      return;
    }

    setFailTarget(order);

    setFailReason("");

    setFailMessage("");
  }

  async function saveFail(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!failTarget || !canUpdate) {
      return;
    }

    const reason = failReason.trim();

    if (!reason) {
      setFailMessage("اكتب سبب فشل التوصيل.");
      return;
    }

    setBusyId(failTarget.id);

    setFailMessage("");

    try {
      const { error } = await supabase.rpc("fail_order_delivery", {
        target_company: companyId,

        target_order: failTarget.id,

        target_reason: reason,
      });

      if (error) {
        setFailMessage(friendlyError(error, "fail"));
        return;
      }

      setFailTarget(null);

      setNotice({
        type: "success",

        text: "تم تسجيل فشل التوصيل وإعادة الطلبية لمسار التجهيز.",
      });

      router.refresh();
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">دورة التوصيل</span>

          <h2>تجهيز وتسليم الطلبات</h2>

          <p className="muted">جهّز تسليمة كاملة أو جزئية، ثم أكد الوصول أو سجل فشل التوصيل.</p>
        </div>

        {canViewMap ? (
          <Link href="/map?mode=deliveries" className="softButton">
            <Icons.map size={14} />
            طريق التوصيل على الخريطة
          </Link>
        ) : null}
      </div>

      {notice ? (
        <div
          className={notice.type === "error" ? "toastError" : "panel panelPad"}
          role={notice.type === "error" ? "alert" : "status"}
          style={{
            marginBottom: 14,
          }}
        >
          {notice.text}
        </div>
      ) : null}

      <section className="statsGrid">
        <Mini title="جاهزة للتوصيل" value={String(initialStats.readyCount)} />

        <Mini title="بالطريق" value={String(initialStats.roadCount)} />

        <Mini title="قطع بالسيارة" value={qty(initialStats.roadUnits)} />

        <Mini title="قطع متبقية" value={qty(initialStats.remainingUnits)} />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        <form
          className="filters"
          onSubmit={(event) => {
            event.preventDefault();

            navigate(search, filter, 1);
          }}
        >
          <div className="searchBox">
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="اسم العميل، الهاتف، المنطقة أو رقم الطلب..."
              aria-label="بحث في التوصيلات"
            />

            <button type="submit" className="softButton">
              بحث
            </button>
          </div>

          <select
            value={filter}
            aria-label="حالة التوصيل"
            onChange={(event) => {
              const value = event.target.value as DeliveryStatusFilter;

              setFilter(value);

              navigate(search, value, 1);
            }}
          >
            <option value="all">كل الحالات</option>

            <option value="ready">جاهزة</option>

            <option value="out_for_delivery">بالطريق</option>
          </select>

          <div />

          <div className="resultCount">{totalCount} نتيجة</div>
        </form>

        {!rows.length ? (
          <div className="empty">
            <Icons.truck size={30} />

            <h3>لا توجد طلبات للتوصيل</h3>

            <p>الطلبات الجاهزة أو الموجودة بالطريق ستظهر هنا.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>العميل</th>
                  <th>الطلبية</th>
                  <th>تقدم التسليم</th>
                  <th>القيمة</th>
                  <th>الحالة</th>
                  <th>تواصل</th>
                  <th>الإجراء</th>
                </tr>
              </thead>

              <tbody>
                {rows.map((order) => {
                  const totalQty = order.items.reduce(
                    (total, item) => total + numeric(item.quantity),
                    0,
                  );

                  const deliveredQty = order.items.reduce(
                    (total, item) => total + numeric(item.delivered_quantity),
                    0,
                  );

                  const activeQty = order.items.reduce(
                    (total, item) => total + numeric(item.active_quantity),
                    0,
                  );

                  const trader = order.trader;

                  return (
                    <tr key={order.id}>
                      <td>
                        <div className="merchant">
                          <div className="merchantLogo">{trader?.name?.charAt(0) || "؟"}</div>

                          <div>
                            <strong>{trader?.name || "عميل"}</strong>

                            <span>{trader?.area || trader?.address || "—"}</span>
                          </div>
                        </div>
                      </td>

                      <td>
                        <strong>{order.order_number ?? `#${order.id.slice(0, 8)}`}</strong>

                        <div className="muted">{order.items.length} أصناف</div>

                        <div className="muted">
                          {formatDateTime(order.ordered_at || order.created_at)}
                        </div>
                      </td>

                      <td>
                        <strong>
                          {qty(deliveredQty)} / {qty(totalQty)}
                        </strong>

                        {activeQty > 0 ? (
                          <div className="muted">{qty(activeQty)} بالطريق</div>
                        ) : null}
                      </td>

                      <td>{money(order.total, currency)}</td>

                      <td>
                        <span className={`chip ${order.status === "ready" ? "orange" : "blue"}`}>
                          {order.status === "ready" ? "جاهز" : "بالطريق"}
                        </span>
                      </td>

                      <td>
                        <div className="rowActions">
                          {trader?.phone ? (
                            <a
                              className="softButton"
                              href={`tel:${trader.phone}`}
                              aria-label={`اتصال بـ ${trader.name}`}
                            >
                              <Icons.phone size={13} />
                            </a>
                          ) : null}

                          {trader?.whatsapp ? (
                            <a
                              className="softButton"
                              target="_blank"
                              rel="noreferrer"
                              href={`https://wa.me/${String(trader.whatsapp).replace(/\D/g, "")}`}
                              aria-label={`واتساب ${trader.name}`}
                            >
                              <Icons.whatsapp size={13} />
                            </a>
                          ) : null}

                          {canViewMap && trader?.latitude != null && trader?.longitude != null ? (
                            <Link
                              className="softButton"
                              href={`/map?trader=${trader.id}`}
                              aria-label={`موقع ${trader.name}`}
                            >
                              <Icons.map size={13} />
                            </Link>
                          ) : null}
                        </div>
                      </td>

                      <td>
                        {canUpdate ? (
                          <div className="rowActions">
                            {order.status === "ready" ? (
                              <button
                                type="button"
                                className="primaryButton"
                                disabled={busyId === order.id}
                                onClick={() => openDelivery(order)}
                              >
                                <Icons.truck size={14} />
                                تجهيز تسليمة
                              </button>
                            ) : (
                              <>
                                <button
                                  type="button"
                                  className="primaryButton"
                                  disabled={busyId === order.id}
                                  onClick={() => openComplete(order)}
                                >
                                  تم التسليم
                                </button>

                                <button
                                  type="button"
                                  className="dangerButton"
                                  disabled={busyId === order.id}
                                  onClick={() => openFail(order)}
                                >
                                  فشل التوصيل
                                </button>
                              </>
                            )}
                          </div>
                        ) : (
                          <span className="muted">عرض فقط</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {pageCount > 1 ? (
          <div
            className="rowActions"
            style={{
              justifyContent: "center",
              padding: 16,
            }}
          >
            <button
              type="button"
              className="softButton"
              disabled={page <= 1}
              onClick={() => navigate(searchQuery, statusFilter, page - 1)}
            >
              السابق
            </button>

            <span className="muted">
              صفحة {page} من {pageCount}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={page >= pageCount}
              onClick={() => navigate(searchQuery, statusFilter, page + 1)}
            >
              التالي
            </button>
          </div>
        ) : null}
      </section>

      {deliveryTarget ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              maxWidth: 850,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">تسليمة جديدة</span>

                <h2>حدد الكميات التي ستخرج</h2>

                <p className="muted">
                  طلب {deliveryTarget.order_number ?? `#${deliveryTarget.id.slice(0, 8)}`}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={busyId === deliveryTarget.id}
                onClick={() => setDeliveryTarget(null)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveDelivery}>
              <div className="rowActions">
                <button type="button" className="softButton" onClick={fillAll}>
                  تعبئة كل المتبقي
                </button>
              </div>

              <div
                className="tableWrap"
                style={{
                  marginTop: 14,
                }}
              >
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الصنف</th>
                      <th>المطلوب</th>
                      <th>مسلّم</th>
                      <th>المتبقي</th>
                      <th>يخرج الآن</th>
                    </tr>
                  </thead>

                  <tbody>
                    {deliveryTarget.items.map((item) => (
                      <tr key={item.id}>
                        <td>
                          <strong>{item.product_name}</strong>

                          <div className="muted">{item.sku || item.unit || "—"}</div>
                        </td>

                        <td>{qty(item.quantity)}</td>

                        <td>{qty(item.delivered_quantity)}</td>

                        <td>{qty(item.remaining_quantity)}</td>

                        <td>
                          <input
                            type="number"
                            min="0"
                            max={item.remaining_quantity}
                            step="0.001"
                            value={quantities[item.id] ?? ""}
                            onChange={(event) =>
                              setQuantities((current) => ({
                                ...current,

                                [item.id]: event.target.value,
                              }))
                            }
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {deliveryMessage ? (
                <div className="toastError" role="alert">
                  {deliveryMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={busyId === deliveryTarget.id}
                  onClick={() => setDeliveryTarget(null)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={busyId === deliveryTarget.id}>
                  {busyId === deliveryTarget.id ? "جارٍ التجهيز..." : "إخراج التسليمة"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {completeTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">تأكيد التسليم</span>

                <h2>وصلت التسليمة للعميل؟</h2>
              </div>
            </div>

            <form onSubmit={saveComplete}>
              <p>
                الطلبية:{" "}
                <strong>
                  {completeTarget.order_number ?? `#${completeTarget.id.slice(0, 8)}`}
                </strong>
              </p>

              <p className="muted">
                عند التأكيد سيتم خصم البضاعة من المخزون، إنهاء الحجز وإنشاء فاتورة بيع لهذه
                التسليمة.
              </p>

              <label className="field">
                <span>ملاحظات التسليم</span>

                <textarea
                  value={completeNotes}
                  onChange={(event) => setCompleteNotes(event.target.value)}
                  placeholder="اختياري"
                />
              </label>

              {completeMessage ? (
                <div className="toastError" role="alert">
                  {completeMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={busyId === completeTarget.id}
                  onClick={() => setCompleteTarget(null)}
                >
                  رجوع
                </button>

                <button className="primaryButton" disabled={busyId === completeTarget.id}>
                  {busyId === completeTarget.id ? "جارٍ التثبيت..." : "تأكيد الوصول"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {failTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">فشل التوصيل</span>

                <h2>إعادة الطلبية لمسار التجهيز</h2>
              </div>
            </div>

            <form onSubmit={saveFail}>
              <p>
                الطلبية:{" "}
                <strong>{failTarget.order_number ?? `#${failTarget.id.slice(0, 8)}`}</strong>
              </p>

              <p className="muted">
                المخزون لم يُخصم بعد، لذلك ستبقى الحجوزات موجودة ويمكن تجهيز تسليمة جديدة لاحقاً.
              </p>

              <label className="field">
                <span>سبب فشل التوصيل *</span>

                <textarea
                  value={failReason}
                  onChange={(event) => setFailReason(event.target.value)}
                  placeholder="مثال: العميل غير موجود، العنوان مغلق..."
                />
              </label>

              {failMessage ? (
                <div className="toastError" role="alert">
                  {failMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={busyId === failTarget.id}
                  onClick={() => setFailTarget(null)}
                >
                  رجوع
                </button>

                <button className="dangerButton" disabled={busyId === failTarget.id}>
                  {busyId === failTarget.id ? "جارٍ التسجيل..." : "تأكيد فشل التوصيل"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
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
