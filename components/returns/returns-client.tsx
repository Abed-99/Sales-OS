"use client";

import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { Icons } from "@/components/icons";
import { useOwnerPin } from "@/components/owner-pin";
import { createClient } from "@/lib/supabase/client";

export type ReturnsTab = "sales" | "purchases" | "history";

export type ReturnHistoryKindFilter = "all" | "sales" | "purchases";

export type ReturnHistoryStatusFilter = "all" | "posted" | "reversed" | "cancelled";

export type ReturnWarehouse = {
  id: string;
  name: string;
  code: string | null;
  is_default: boolean;
};

export type SalesReturnCandidateItem = {
  id: string;
  product_id: string;
  product_name: string;
  sku: string | null;
  description: string;
  unit: string | null;
  invoiced_quantity: number;
  returned_quantity: number;
  available_quantity: number;
};

export type SalesReturnCandidate = {
  id: string;
  invoice_number: string;
  invoice_date: string;
  currency: string;
  total: number;

  trader: {
    id: string;
    name: string;
  } | null;

  items: SalesReturnCandidateItem[];
};

export type PurchaseReturnCandidateItem = {
  id: string;
  product_id: string;
  product_name: string;
  sku: string | null;
  description: string | null;
  invoiced_quantity: number;
  received_quantity: number;
  returned_quantity: number;
  available_quantity: number;
};

export type PurchaseReturnCandidate = {
  id: string;
  invoice_number: string;
  supplier_invoice_number: string | null;
  invoice_date: string;
  currency: string;
  total: number;

  supplier: {
    id: string;
    name: string;
  } | null;

  items: PurchaseReturnCandidateItem[];
};

export type ReturnHistoryRow = {
  id: string;

  kind: "sales" | "purchases";

  return_number: string;
  invoice_number: string;
  party_name: string;
  warehouse_name: string;

  return_date: string;

  status: "posted" | "reversed" | "cancelled";

  currency: string;
  total: number;

  notes: string | null;

  created_at: string;

  reversed_at: string | null;

  reversal_reason: string | null;
};

export type ReturnsStats = {
  salesCount: number;
  salesPostedCount: number;
  salesReversedCount: number;

  purchaseCount: number;
  purchasePostedCount: number;
  purchaseReversedCount: number;

  salesTotals: {
    currency: string;
    total: number;
  }[];

  purchaseTotals: {
    currency: string;
    total: number;
  }[];
};

type Notice = {
  type: "success" | "error";

  text: string;
};

function numeric(value: unknown) {
  const result = Number(value ?? 0);

  return Number.isFinite(result) ? result : 0;
}

function quantity(value: unknown) {
  return numeric(value).toFixed(3);
}

function money(value: unknown, currency: string) {
  return `${new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(numeric(value))} ${currency}`;
}

function formatTotals(
  rows: {
    currency: string;
    total: number;
  }[],
) {
  if (!rows.length) {
    return "0.00";
  }

  return rows.map((row) => money(row.total, row.currency)).join(" • ");
}

function businessDate() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());

  const year = parts.find((part) => part.type === "year")?.value;

  const month = parts.find((part) => part.type === "month")?.value;

  const day = parts.find((part) => part.type === "day")?.value;

  return `${year}-${month}-${day}`;
}

function friendlyError(
  error: {
    code?: string;
    message?: string;
  } | null,
  action: "create" | "reverse",
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

  if (message.includes("finance period") && message.includes("closed")) {
    return "الفترة المحاسبية لهذا التاريخ مغلقة.";
  }

  if (message.includes("return date cannot be before invoice date")) {
    return "تاريخ المرتجع لا يمكن أن يكون قبل تاريخ الفاتورة.";
  }

  if (message.includes("return date cannot be in the future")) {
    return "تاريخ المرتجع لا يمكن أن يكون بالمستقبل.";
  }

  if (message.includes("posted sales invoice not found")) {
    return "فاتورة البيع غير موجودة أو لم تعد مرحلة.";
  }

  if (message.includes("posted purchase invoice not found")) {
    return "فاتورة الشراء غير موجودة أو لم تعد مرحلة.";
  }

  if (message.includes("invalid warehouse")) {
    return "المستودع غير صالح أو أصبح غير نشط.";
  }

  if (message.includes("return quantity must be greater than zero")) {
    return "كمية المرتجع يجب أن تكون أكبر من صفر.";
  }

  if (message.includes("returned quantity exceeds invoiced quantity")) {
    return "الكمية المرتجعة أكبر من الكمية المباعة المتاحة للإرجاع.";
  }

  if (message.includes("returned quantity exceeds received quantity")) {
    return "الكمية المرتجعة أكبر من الكمية المستلمة فعلياً.";
  }

  if (message.includes("not enough available stock")) {
    return "المخزون المتاح غير كافٍ لإتمام مرتجع الشراء.";
  }

  if (message.includes("reversal reason required")) {
    return "سبب عكس المرتجع مطلوب.";
  }

  if (message.includes("only posted") && message.includes("return")) {
    return "يمكن عكس المرتجعات المرحلة فقط.";
  }

  if (message.includes("already reserved") || message.includes("transferred or used")) {
    return "لا يمكن عكس مرتجع المبيعات لأن البضاعة المرتجعة تم حجزها أو نقلها أو استخدامها.";
  }

  if (message.includes("original inventory cost")) {
    return "تعذر العثور على حركة المخزون الأصلية لهذا المرتجع.";
  }

  if (message.includes("financial journal") || message.includes("original journal")) {
    return "تعذر عكس القيد المحاسبي المرتبط بالمرتجع.";
  }

  if (action === "reverse") {
    return "تعذر عكس المرتجع.";
  }

  return "تعذر إنشاء المرتجع. راجع البيانات وحاول مرة ثانية.";
}

function statusLabel(status: ReturnHistoryRow["status"]) {
  if (status === "posted") {
    return "مرحّل";
  }

  if (status === "reversed") {
    return "معكوس";
  }

  return "ملغى";
}

function statusColor(status: ReturnHistoryRow["status"]) {
  if (status === "posted") {
    return "green";
  }

  return "gray";
}

export function ReturnsClient({
  companyId,
  initialTab,
  initialStats,
  warehouses,
  salesCandidates,
  purchaseCandidates,
  historyRows,
  totalCount,
  page,
  pageSize,
  searchQuery,
  historyKind,
  historyStatus,
  canCreate,
  canReverse,
  initialError,
}: {
  companyId: string;

  initialTab: ReturnsTab;

  initialStats: ReturnsStats;

  warehouses: ReturnWarehouse[];

  salesCandidates: SalesReturnCandidate[];

  purchaseCandidates: PurchaseReturnCandidate[];

  historyRows: ReturnHistoryRow[];

  totalCount: number;

  page: number;
  pageSize: number;

  searchQuery: string;

  historyKind: ReturnHistoryKindFilter;

  historyStatus: ReturnHistoryStatusFilter;

  canCreate: boolean;
  canReverse: boolean;

  initialError: string | null;
}) {
  const [supabase] = useState(() => createClient());

  const router = useRouter();

  const searchParams = useSearchParams();

  const [tab, setTab] = useState<ReturnsTab>(initialTab);

  const [search, setSearch] = useState(searchQuery);

  const [kindFilter, setKindFilter] = useState<ReturnHistoryKindFilter>(historyKind);

  const [statusFilter, setStatusFilter] = useState<ReturnHistoryStatusFilter>(historyStatus);

  const [notice, setNotice] = useState<Notice | null>(
    initialError
      ? {
          type: "error",

          text: initialError,
        }
      : null,
  );

  const [warehouseId, setWarehouseId] = useState(
    warehouses.find((warehouse) => warehouse.is_default)?.id ?? warehouses[0]?.id ?? "",
  );

  const [returnDate, setReturnDate] = useState(businessDate());

  const [notes, setNotes] = useState("");

  const [quantities, setQuantities] = useState<Record<string, string>>({});

  const [salesTarget, setSalesTarget] = useState<SalesReturnCandidate | null>(null);

  const [purchaseTarget, setPurchaseTarget] = useState<PurchaseReturnCandidate | null>(null);

  // أسطر المرتجع اللي رجعت خربانة.
  const [damagedLines, setDamagedLines] = useState<Record<string, boolean>>({});

  const ownerPin = useOwnerPin(supabase, companyId);

  const [reverseTarget, setReverseTarget] = useState<ReturnHistoryRow | null>(null);

  const [reverseReason, setReverseReason] = useState("");

  const [formMessage, setFormMessage] = useState("");

  const [reverseMessage, setReverseMessage] = useState("");

  const [saving, setSaving] = useState(false);

  const [busyReturn, setBusyReturn] = useState<string | null>(null);

  useEffect(() => {
    setTab(initialTab);

    setSearch(searchQuery);

    setKindFilter(historyKind);

    setStatusFilter(historyStatus);
  }, [initialTab, searchQuery, historyKind, historyStatus]);

  useEffect(() => {
    if (initialError) {
      setNotice({
        type: "error",
        text: initialError,
      });
    }
  }, [initialError]);

  useEffect(() => {
    if (!warehouses.length) {
      setWarehouseId("");
      return;
    }

    if (warehouses.some((warehouse) => warehouse.id === warehouseId)) {
      return;
    }

    setWarehouseId(warehouses.find((warehouse) => warehouse.is_default)?.id ?? warehouses[0].id);
  }, [warehouses, warehouseId]);

  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));

  function navigate({
    nextTab = tab,
    nextSearch = search,
    nextPage = 1,
    nextKind = kindFilter,
    nextStatus = statusFilter,
  }: {
    nextTab?: ReturnsTab;

    nextSearch?: string;

    nextPage?: number;

    nextKind?: ReturnHistoryKindFilter;

    nextStatus?: ReturnHistoryStatusFilter;
  }) {
    const params = new URLSearchParams(searchParams.toString());

    params.set("tab", nextTab);

    const clean = nextSearch.trim();

    if (clean) {
      params.set("q", clean);
    } else {
      params.delete("q");
    }

    if (nextPage > 1) {
      params.set("page", String(nextPage));
    } else {
      params.delete("page");
    }

    if (nextTab === "history") {
      if (nextKind !== "all") {
        params.set("kind", nextKind);
      } else {
        params.delete("kind");
      }

      if (nextStatus !== "all") {
        params.set("status", nextStatus);
      } else {
        params.delete("status");
      }
    } else {
      params.delete("kind");

      params.delete("status");
    }

    router.push(`/returns?${params.toString()}`);
  }

  function switchTab(nextTab: ReturnsTab) {
    if (!canCreate && nextTab !== "history") {
      return;
    }

    setTab(nextTab);

    setSearch("");

    navigate({
      nextTab,
      nextSearch: "",
      nextPage: 1,
    });
  }

  function openSalesReturn(invoice: SalesReturnCandidate) {
    if (!canCreate) {
      return;
    }

    setDamagedLines({});

    const next: Record<string, string> = {};

    for (const item of invoice.items) {
      next[item.id] = "";
    }

    setQuantities(next);

    setReturnDate(businessDate());

    setNotes("");
    setFormMessage("");

    setSalesTarget(invoice);

    setPurchaseTarget(null);
  }

  function openPurchaseReturn(invoice: PurchaseReturnCandidate) {
    if (!canCreate) {
      return;
    }

    const next: Record<string, string> = {};

    for (const item of invoice.items) {
      next[item.id] = "";
    }

    setQuantities(next);

    setReturnDate(businessDate());

    setNotes("");
    setFormMessage("");

    setPurchaseTarget(invoice);

    setSalesTarget(null);
  }

  async function saveSalesReturn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!salesTarget || !canCreate || saving) {
      return;
    }

    setFormMessage("");

    if (!warehouseId) {
      setFormMessage("لا يوجد مستودع صالح للمرتجع.");
      return;
    }

    if (!returnDate) {
      setFormMessage("حدد تاريخ المرتجع.");
      return;
    }

    if (returnDate < salesTarget.invoice_date) {
      setFormMessage("تاريخ المرتجع لا يمكن أن يكون قبل تاريخ الفاتورة.");
      return;
    }

    if (returnDate > businessDate()) {
      setFormMessage("تاريخ المرتجع لا يمكن أن يكون بالمستقبل.");
      return;
    }

    const payload: Array<{
      sales_invoice_item_id: string;
      quantity: number;
      damaged?: boolean;
    }> = [];

    for (const item of salesTarget.items) {
      const value = numeric(quantities[item.id]);

      const available = numeric(item.available_quantity);

      if (value < 0) {
        setFormMessage("كمية المرتجع لا يمكن أن تكون سالبة.");
        return;
      }

      if (value > available + 0.0005) {
        setFormMessage(`كمية ${item.product_name} أكبر من المتاح للإرجاع.`);
        return;
      }

      if (value > 0) {
        payload.push({
          sales_invoice_item_id: item.id,

          quantity: Number(value.toFixed(3)),

          damaged: Boolean(damagedLines[item.id]),
        });
      }
    }

    if (!payload.length) {
      setFormMessage("اكتب كمية مرتجعة لصنف واحد على الأقل.");
      return;
    }

    setSaving(true);

    try {
      const { error } = await supabase.rpc("create_sales_return", {
        target_company: companyId,

        target_invoice: salesTarget.id,

        target_warehouse: warehouseId,

        target_date: returnDate,

        target_notes: notes.trim() || null,

        items_payload: payload,
      });

      if (error) {
        setFormMessage(friendlyError(error, "create"));
        return;
      }

      setSalesTarget(null);

      setNotice({
        type: "success",

        text: "تم ترحيل مرتجع المبيعات وتحديث المخزون والمحاسبة.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  async function savePurchaseReturn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!purchaseTarget || !canCreate || saving) {
      return;
    }

    setFormMessage("");

    if (!warehouseId) {
      setFormMessage("لا يوجد مستودع صالح للمرتجع.");
      return;
    }

    if (!returnDate) {
      setFormMessage("حدد تاريخ المرتجع.");
      return;
    }

    if (returnDate < purchaseTarget.invoice_date) {
      setFormMessage("تاريخ المرتجع لا يمكن أن يكون قبل تاريخ الفاتورة.");
      return;
    }

    if (returnDate > businessDate()) {
      setFormMessage("تاريخ المرتجع لا يمكن أن يكون بالمستقبل.");
      return;
    }

    const payload: Array<{
      purchase_invoice_item_id: string;

      quantity: number;
    }> = [];

    for (const item of purchaseTarget.items) {
      const value = numeric(quantities[item.id]);

      const available = numeric(item.available_quantity);

      if (value < 0) {
        setFormMessage("كمية المرتجع لا يمكن أن تكون سالبة.");
        return;
      }

      if (value > available + 0.0005) {
        setFormMessage(`كمية ${item.product_name} أكبر من الكمية المستلمة المتاحة للإرجاع.`);
        return;
      }

      if (value > 0) {
        payload.push({
          purchase_invoice_item_id: item.id,

          quantity: Number(value.toFixed(3)),
        });
      }
    }

    if (!payload.length) {
      setFormMessage("اكتب كمية مرتجعة لصنف واحد على الأقل.");
      return;
    }

    setSaving(true);

    try {
      const { error } = await supabase.rpc("create_purchase_return", {
        target_company: companyId,

        target_invoice: purchaseTarget.id,

        target_warehouse: warehouseId,

        target_date: returnDate,

        target_notes: notes.trim() || null,

        items_payload: payload,
      });

      if (error) {
        setFormMessage(friendlyError(error, "create"));
        return;
      }

      setPurchaseTarget(null);

      setNotice({
        type: "success",

        text: "تم ترحيل مرتجع المشتريات وتحديث المخزون والمحاسبة.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  function openReverse(row: ReturnHistoryRow) {
    if (row.status !== "posted") {
      return;
    }

    setReverseTarget(row);

    setReverseReason("");

    setReverseMessage("");
  }

  async function saveReverse(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!reverseTarget) {
      return;
    }

    const reason = reverseReason.trim();

    if (!reason) {
      setReverseMessage("اكتب سبب عكس المرتجع.");
      return;
    }

    setBusyReturn(reverseTarget.id);

    setReverseMessage("");

    try {
      const run = () =>
        supabase.rpc(
          reverseTarget.kind === "sales" ? "reverse_sales_return" : "reverse_purchase_return",
          {
            target_company: companyId,
            target_return: reverseTarget.id,
            target_reason: reason,
          },
        );

      let { error } = await run();

      // بدون صلاحية العكس: المالك بيكتب رمزو قدام الموظف.
      if (error?.message.toLowerCase().includes("not allowed") && !canReverse) {
        if (await ownerPin.ask("reverse_return", "عكس مرتجع بدو صلاحية أو موافقة المالك.")) {
          ({ error } = await run());
        }
      }

      if (error) {
        setReverseMessage(friendlyError(error, "reverse"));
        return;
      }

      setReverseTarget(null);

      setNotice({
        type: "success",

        text: "تم عكس المرتجع وحركة المخزون والقيد المحاسبي.",
      });

      router.refresh();
    } finally {
      setBusyReturn(null);
    }
  }

  return (
    <div className="page">
      {ownerPin.modal}
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المرتجعات</span>

          <h2>المرتجعات</h2>

          <p className="muted">مرتجعات العملاء والموردين مرتبطة بالمخزون والمحاسبة تلقائياً.</p>
        </div>
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
        <Mini
          title="مرتجعات المبيعات"
          value={String(initialStats.salesCount)}
          subtitle={`${initialStats.salesPostedCount} مرحلة • ${initialStats.salesReversedCount} معكوسة`}
        />

        <Mini
          title="قيمة مرتجعات المبيعات المرحلة"
          value={formatTotals(initialStats.salesTotals)}
        />

        <Mini
          title="مرتجعات المشتريات"
          value={String(initialStats.purchaseCount)}
          subtitle={`${initialStats.purchasePostedCount} مرحلة • ${initialStats.purchaseReversedCount} معكوسة`}
        />

        <Mini
          title="قيمة مرتجعات المشتريات المرحلة"
          value={formatTotals(initialStats.purchaseTotals)}
        />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        {canCreate ? (
          <>
            <button
              type="button"
              className={tab === "sales" ? "primaryButton" : "softButton"}
              onClick={() => switchTab("sales")}
            >
              مرتجع مبيعات
            </button>

            <button
              type="button"
              className={tab === "purchases" ? "primaryButton" : "softButton"}
              onClick={() => switchTab("purchases")}
            >
              مرتجع مشتريات
            </button>
          </>
        ) : null}

        <button
          type="button"
          className={tab === "history" ? "primaryButton" : "softButton"}
          onClick={() => switchTab("history")}
        >
          سجل المرتجعات
        </button>
      </div>

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

            navigate({
              nextSearch: search,
              nextPage: 1,
            });
          }}
        >
          <div className="searchBox">
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={
                tab === "sales"
                  ? "رقم الفاتورة أو الطلبية، اسم العميل أو الصنف..."
                  : tab === "purchases"
                    ? "رقم الفاتورة، اسم المورد أو الصنف..."
                    : "رقم المرتجع، الفاتورة، اسم العميل/المورد أو الصنف..."
              }
              aria-label="بحث في المرتجعات"
            />

            <button type="submit" className="softButton">
              بحث
            </button>
          </div>

          {tab === "history" ? (
            <>
              <select
                value={kindFilter}
                aria-label="نوع المرتجع"
                onChange={(event) => {
                  const value = event.target.value as ReturnHistoryKindFilter;

                  setKindFilter(value);

                  navigate({
                    nextKind: value,
                    nextPage: 1,
                  });
                }}
              >
                <option value="all">كل الأنواع</option>

                <option value="sales">مبيعات</option>

                <option value="purchases">مشتريات</option>
              </select>

              <select
                value={statusFilter}
                aria-label="حالة المرتجع"
                onChange={(event) => {
                  const value = event.target.value as ReturnHistoryStatusFilter;

                  setStatusFilter(value);

                  navigate({
                    nextStatus: value,
                    nextPage: 1,
                  });
                }}
              >
                <option value="all">كل الحالات</option>

                <option value="posted">مرحّل</option>

                <option value="reversed">معكوس</option>

                <option value="cancelled">ملغى</option>
              </select>
            </>
          ) : (
            <div />
          )}

          <div className="resultCount">{totalCount} نتيجة</div>
        </form>

        {tab === "sales" ? (
          <SalesCandidatesTable
            rows={salesCandidates}
            canCreate={canCreate}
            onReturn={openSalesReturn}
          />
        ) : null}

        {tab === "purchases" ? (
          <PurchaseCandidatesTable
            rows={purchaseCandidates}
            canCreate={canCreate}
            onReturn={openPurchaseReturn}
          />
        ) : null}

        {tab === "history" ? (
          <HistoryTable
            rows={historyRows}
            canReverse={canReverse}
            busyReturn={busyReturn}
            onReverse={openReverse}
          />
        ) : null}

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
              onClick={() =>
                navigate({
                  nextSearch: searchQuery,
                  nextPage: page - 1,
                  nextKind: historyKind,
                  nextStatus: historyStatus,
                })
              }
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
              onClick={() =>
                navigate({
                  nextSearch: searchQuery,
                  nextPage: page + 1,
                  nextKind: historyKind,
                  nextStatus: historyStatus,
                })
              }
            >
              التالي
            </button>
          </div>
        ) : null}
      </section>

      {salesTarget ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              maxWidth: 900,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">Sales Return</span>

                <h2>مرتجع فاتورة {salesTarget.invoice_number}</h2>

                <p className="muted">{salesTarget.trader?.name || "عميل"}</p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setSalesTarget(null)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveSalesReturn}>
              <ReturnHeader
                warehouses={warehouses}
                warehouseId={warehouseId}
                setWarehouseId={setWarehouseId}
                date={returnDate}
                setDate={setReturnDate}
                minDate={salesTarget.invoice_date}
              />

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
                      <th>مباع</th>
                      <th>مرتجع سابق</th>
                      <th>متاح</th>
                      <th>الكمية</th>
                      <th>تالف؟</th>
                    </tr>
                  </thead>

                  <tbody>
                    {salesTarget.items.map((item) => (
                      <tr key={item.id}>
                        <td>
                          <strong>{item.product_name}</strong>

                          <div className="muted">{item.sku || item.unit || item.description}</div>
                        </td>

                        <td>{quantity(item.invoiced_quantity)}</td>

                        <td>{quantity(item.returned_quantity)}</td>

                        <td>{quantity(item.available_quantity)}</td>

                        <td>
                          <input
                            type="number"
                            min="0"
                            max={item.available_quantity}
                            step="0.001"
                            value={quantities[item.id] ?? ""}
                            onChange={(event) =>
                              setQuantities((current) => ({
                                ...current,

                                [item.id]: event.target.value,
                              }))
                            }
                            style={{
                              minWidth: 100,
                            }}
                          />
                        </td>

                        <td>
                          <input
                            type="checkbox"
                            title="البضاعة رجعت خربانة: ما بترجع للمخزون وبتنحسب خسارة تلف"
                            checked={Boolean(damagedLines[item.id])}
                            onChange={(event) =>
                              setDamagedLines((current) => ({
                                ...current,
                                [item.id]: event.target.checked,
                              }))
                            }
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <Notes value={notes} setValue={setNotes} />

              {formMessage ? (
                <div className="toastError" role="alert">
                  {formMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setSalesTarget(null)}
                >
                  إلغاء
                </button>

                <button type="submit" className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الترحيل..." : "ترحيل مرتجع المبيعات"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {purchaseTarget ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              maxWidth: 900,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">Purchase Return</span>

                <h2>مرتجع فاتورة {purchaseTarget.invoice_number}</h2>

                <p className="muted">{purchaseTarget.supplier?.name || "مورد"}</p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setPurchaseTarget(null)}
              >
                ×
              </button>
            </div>

            <form onSubmit={savePurchaseReturn}>
              <ReturnHeader
                warehouses={warehouses}
                warehouseId={warehouseId}
                setWarehouseId={setWarehouseId}
                date={returnDate}
                setDate={setReturnDate}
                minDate={purchaseTarget.invoice_date}
              />

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
                      <th>بالفاتورة</th>
                      <th>مستلم فعلياً</th>
                      <th>مرتجع سابق</th>
                      <th>متاح</th>
                      <th>الكمية</th>
                    </tr>
                  </thead>

                  <tbody>
                    {purchaseTarget.items.map((item) => (
                      <tr key={item.id}>
                        <td>
                          <strong>{item.product_name}</strong>

                          <div className="muted">{item.sku || item.description || ""}</div>
                        </td>

                        <td>{quantity(item.invoiced_quantity)}</td>

                        <td>{quantity(item.received_quantity)}</td>

                        <td>{quantity(item.returned_quantity)}</td>

                        <td>{quantity(item.available_quantity)}</td>

                        <td>
                          <input
                            type="number"
                            min="0"
                            max={item.available_quantity}
                            step="0.001"
                            value={quantities[item.id] ?? ""}
                            onChange={(event) =>
                              setQuantities((current) => ({
                                ...current,

                                [item.id]: event.target.value,
                              }))
                            }
                            style={{
                              minWidth: 100,
                            }}
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <Notes value={notes} setValue={setNotes} />

              {formMessage ? (
                <div className="toastError" role="alert">
                  {formMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setPurchaseTarget(null)}
                >
                  إلغاء
                </button>

                <button type="submit" className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الترحيل..." : "ترحيل مرتجع المشتريات"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {reverseTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">عكس مرتجع</span>

                <h2>{reverseTarget.return_number}</h2>
              </div>
            </div>

            <form onSubmit={saveReverse}>
              <p>سيتم عكس حركة المخزون والقيد المحاسبي للمرتجع.</p>

              <p className="muted">
                {reverseTarget.kind === "sales" ? "مرتجع مبيعات" : "مرتجع مشتريات"} • فاتورة{" "}
                {reverseTarget.invoice_number}
              </p>

              <label className="field">
                <span>سبب العكس *</span>

                <textarea
                  value={reverseReason}
                  onChange={(event) => setReverseReason(event.target.value)}
                  placeholder="اكتب سبب واضح لعكس المرتجع..."
                />
              </label>

              {reverseMessage ? (
                <div className="toastError" role="alert">
                  {reverseMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={busyReturn === reverseTarget.id}
                  onClick={() => setReverseTarget(null)}
                >
                  رجوع
                </button>

                <button
                  type="submit"
                  className="dangerButton"
                  disabled={busyReturn === reverseTarget.id}
                >
                  {busyReturn === reverseTarget.id ? "جارٍ العكس..." : "تأكيد عكس المرتجع"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function SalesCandidatesTable({
  rows,
  canCreate,
  onReturn,
}: {
  rows: SalesReturnCandidate[];

  canCreate: boolean;

  onReturn: (row: SalesReturnCandidate) => void;
}) {
  if (!rows.length) {
    return (
      <div className="empty">
        <Icons.box size={28} />

        <h3>لا توجد فواتير بيع قابلة للإرجاع</h3>

        <p>الفواتير المرحلة التي بقي فيها كمية قابلة للإرجاع ستظهر هنا.</p>
      </div>
    );
  }

  return (
    <div className="tableWrap">
      <table className="dataTable">
        <thead>
          <tr>
            <th>الفاتورة</th>

            <th>العميل</th>

            <th>التاريخ</th>

            <th>القيمة</th>

            <th>أصناف قابلة للإرجاع</th>

            <th>الإجراء</th>
          </tr>
        </thead>

        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <td>
                <strong>{row.invoice_number}</strong>
              </td>

              <td>{row.trader?.name || "—"}</td>

              <td>{row.invoice_date}</td>

              <td>{money(row.total, row.currency)}</td>

              <td>{row.items.length}</td>

              <td>
                {canCreate ? (
                  <button type="button" className="primaryButton" onClick={() => onReturn(row)}>
                    إنشاء مرتجع
                  </button>
                ) : (
                  <span className="muted">عرض فقط</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function PurchaseCandidatesTable({
  rows,
  canCreate,
  onReturn,
}: {
  rows: PurchaseReturnCandidate[];

  canCreate: boolean;

  onReturn: (row: PurchaseReturnCandidate) => void;
}) {
  if (!rows.length) {
    return (
      <div className="empty">
        <Icons.box size={28} />

        <h3>لا توجد فواتير شراء قابلة للإرجاع</h3>

        <p>تظهر هنا فقط الكميات التي تم استلامها فعلياً وما زالت قابلة للإرجاع للمورد.</p>
      </div>
    );
  }

  return (
    <div className="tableWrap">
      <table className="dataTable">
        <thead>
          <tr>
            <th>الفاتورة</th>

            <th>فاتورة المورد</th>

            <th>المورد</th>

            <th>التاريخ</th>

            <th>القيمة</th>

            <th>أصناف قابلة للإرجاع</th>

            <th>الإجراء</th>
          </tr>
        </thead>

        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <td>
                <strong>{row.invoice_number}</strong>
              </td>

              <td>{row.supplier_invoice_number || "—"}</td>

              <td>{row.supplier?.name || "—"}</td>

              <td>{row.invoice_date}</td>

              <td>{money(row.total, row.currency)}</td>

              <td>{row.items.length}</td>

              <td>
                {canCreate ? (
                  <button type="button" className="primaryButton" onClick={() => onReturn(row)}>
                    إنشاء مرتجع
                  </button>
                ) : (
                  <span className="muted">عرض فقط</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function HistoryTable({
  rows,
  canReverse,
  busyReturn,
  onReverse,
}: {
  rows: ReturnHistoryRow[];

  canReverse: boolean;

  busyReturn: string | null;

  onReverse: (row: ReturnHistoryRow) => void;
}) {
  if (!rows.length) {
    return (
      <div className="empty">
        <Icons.box size={28} />

        <h3>لا يوجد سجل مرتجعات</h3>
      </div>
    );
  }

  return (
    <div className="tableWrap">
      <table className="dataTable">
        <thead>
          <tr>
            <th>المرتجع</th>

            <th>النوع</th>

            <th>الفاتورة</th>

            <th>العميل / المورد</th>

            <th>المستودع</th>

            <th>التاريخ</th>

            <th>المبلغ</th>

            <th>الحالة</th>

            <th>الإجراء</th>
          </tr>
        </thead>

        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <td>
                <strong>{row.return_number}</strong>

                {row.reversal_reason ? (
                  <div className="muted">سبب العكس: {row.reversal_reason}</div>
                ) : null}
              </td>

              <td>{row.kind === "sales" ? "مبيعات" : "مشتريات"}</td>

              <td>{row.invoice_number}</td>

              <td>{row.party_name}</td>

              <td>{row.warehouse_name}</td>

              <td>{row.return_date}</td>

              <td>{money(row.total, row.currency)}</td>

              <td>
                <span className={`chip ${statusColor(row.status)}`}>{statusLabel(row.status)}</span>
              </td>

              <td>
                {row.status === "posted" ? (
                  <button
                    type="button"
                    className="dangerButton"
                    disabled={busyReturn === row.id}
                    onClick={() => onReverse(row)}
                  >
                    {busyReturn === row.id ? "جارٍ العكس..." : "عكس المرتجع"}
                  </button>
                ) : (
                  <span className="muted">—</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ReturnHeader({
  warehouses,
  warehouseId,
  setWarehouseId,
  date,
  setDate,
  minDate,
}: {
  warehouses: ReturnWarehouse[];

  warehouseId: string;

  setWarehouseId: (value: string) => void;

  date: string;

  setDate: (value: string) => void;

  minDate: string;
}) {
  return (
    <div className="formGrid">
      <label className="field">
        <span>المستودع</span>

        <select value={warehouseId} onChange={(event) => setWarehouseId(event.target.value)}>
          <option value="">اختر المستودع</option>

          {warehouses.map((warehouse) => (
            <option key={warehouse.id} value={warehouse.id}>
              {warehouse.name}
              {warehouse.code ? ` - ${warehouse.code}` : ""}
            </option>
          ))}
        </select>
      </label>

      <label className="field">
        <span>تاريخ المرتجع</span>

        <input
          type="date"
          min={minDate}
          max={businessDate()}
          value={date}
          onChange={(event) => setDate(event.target.value)}
        />
      </label>
    </div>
  );
}

function Notes({
  value,
  setValue,
}: {
  value: string;

  setValue: (value: string) => void;
}) {
  return (
    <label
      className="field"
      style={{
        marginTop: 14,
      }}
    >
      <span>ملاحظات</span>

      <textarea
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder="اختياري"
      />
    </label>
  );
}

function Mini({ title, value, subtitle }: { title: string; value: string; subtitle?: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>

      <div className="statValue">{value}</div>

      {subtitle ? <div className="muted">{subtitle}</div> : null}
    </div>
  );
}
