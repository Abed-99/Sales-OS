"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { Icons } from "@/components/icons";
import { SearchPicker } from "@/components/search-picker";
import { useQuickCreate } from "@/components/quick-create";
import { UnitToggle } from "@/components/unit-toggle";
import { approveWithOwnerPin, useOwnerPin } from "@/components/owner-pin";
import {
  convertPrice,
  toBasePrice,
  toBaseQuantity,
  traderPrices,
  type UnitMode,
} from "@/lib/units";
import { productOption, searchProducts, searchTraders, type ProductPick } from "@/lib/pickers";
import { createClient } from "@/lib/supabase/client";
import { NumberInput } from "@/components/number-input";
import { formatMoney as money, formatQty, todayDamascus as businessDateInput, formatDate } from "@/lib/format";

export type QuoteStatus = "draft" | "sent" | "accepted" | "rejected" | "cancelled" | "converted";

export type QuoteStatusFilter = "all" | QuoteStatus | "expired";

export type QuoteTrader = {
  id: string;
  name: string;
  area: string | null;
  status: string;
};

export type QuoteProduct = {
  id: string;
  name: string;
  sku: string | null;
  sale_price: number | null;
  unit: string;
  active: boolean;
  pack_size?: number | null;
  pack_unit?: string | null;
};

export type QuoteItem = {
  id: string;
  product_id: string;
  quantity: number;
  sale_unit_price: number;
  line_total: number;
  product_name: string;
  sku: string | null;
  unit: string | null;
};

export type QuoteRow = {
  id: string;
  trader_id: string;
  quote_number: string;
  quote_date: string;
  valid_until: string | null;
  status: QuoteStatus;
  currency: string;
  subtotal: number;
  total: number;
  notes: string | null;
  accepted_at: string | null;
  converted_order_id: string | null;
  source?: "manual" | "catalog";
  created_at: string;
  expired: boolean;

  trader: {
    id: string;
    name: string;
    area: string | null;
  } | null;

  items: QuoteItem[];
};

export type QuotesStats = {
  allCount: number;
  openCount: number;
  acceptedCount: number;
  convertedCount: number;
  expiredOpenCount: number;
};

type DraftItem = {
  key: string;
  product_id: string;
  quantity: string;
  sale_unit_price: string;
  mode?: UnitMode;
  unit?: string | null;
  pack_size?: number | null;
  pack_unit?: string | null;
};

type Notice = {
  type: "success" | "error";
  text: string;
};

type LifecycleAction = "sent" | "accepted" | "rejected" | "cancelled";

function numberValue(value: unknown) {
  const result = Number(value ?? 0);

  return Number.isFinite(result) ? result : 0;
}

function emptyItem(): DraftItem {
  return {
    key: crypto.randomUUID(),
    product_id: "",
    quantity: "1",
    sale_unit_price: "",
  };
}

const statusLabels: Record<QuoteStatus, string> = {
  draft: "مسودة",
  sent: "مرسل",
  accepted: "مقبول",
  rejected: "مرفوض",
  cancelled: "ملغي",
  converted: "تحوّل لطلبية",
};

function statusColor(status: QuoteStatus) {
  if (status === "accepted" || status === "converted") {
    return "green";
  }

  if (status === "rejected" || status === "cancelled") {
    return "gray";
  }

  if (status === "sent") {
    return "blue";
  }

  return "orange";
}

function friendlyError(
  error: {
    code?: string;
    message?: string;
  } | null,
  action: "create" | "status" | "convert",
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

  if (message.includes("invalid trader")) {
    return "العميل غير صالح أو أصبح غير نشط.";
  }

  if (message.includes("invalid or inactive product")) {
    return "أحد الأصناف غير صالح أو أصبح غير نشط.";
  }

  if (message.includes("duplicate products")) {
    return "لا يمكن إضافة نفس الصنف أكثر من مرة.";
  }

  if (message.includes("validity date cannot be in the past")) {
    return "تاريخ صلاحية العرض لا يمكن أن يكون بالماضي.";
  }

  if (message.includes("quote not found")) {
    return "عرض السعر غير موجود أو لم يعد متاحاً.";
  }

  if (message.includes("quote has expired")) {
    return "انتهت صلاحية عرض السعر.";
  }

  if (message.includes("quote must be accepted first")) {
    return "يجب قبول عرض السعر قبل تحويله إلى طلبية.";
  }

  if (message.includes("quote already converted")) {
    return "تم تحويل هذا العرض إلى طلبية مسبقاً.";
  }

  if (
    message.includes("invalid quote status transition") ||
    message.includes("quote status cannot be changed")
  ) {
    return "لا يمكن تغيير حالة العرض بهذه الطريقة.";
  }

  if (
    message.includes("order payload does not match quote") ||
    message.includes("quote trader mismatch")
  ) {
    return "بيانات العرض تغيّرت أو لم تعد متطابقة. حدّث الصفحة وحاول مجدداً.";
  }

  if (action === "create") {
    return "تعذر إنشاء عرض السعر. راجع البيانات وحاول مرة ثانية.";
  }

  if (action === "convert") {
    return "تعذر تحويل عرض السعر إلى طلبية.";
  }

  return "تعذر تحديث حالة عرض السعر.";
}

function lifecycleTitle(action: LifecycleAction) {
  if (action === "sent") {
    return "إرسال عرض السعر";
  }

  if (action === "accepted") {
    return "قبول عرض السعر";
  }

  if (action === "rejected") {
    return "رفض عرض السعر";
  }

  return "إلغاء عرض السعر";
}

function lifecycleDescription(action: LifecycleAction) {
  if (action === "sent") {
    return "سيتم تحويل العرض من مسودة إلى عرض مرسل للعميل.";
  }

  if (action === "accepted") {
    return "سيتم اعتماد العرض، وبعدها يصبح قابلاً للتحويل إلى طلبية.";
  }

  if (action === "rejected") {
    return "سيتم تسجيل أن العميل رفض العرض، ولن يمكن إعادة فتحه.";
  }

  return "سيتم إلغاء العرض ولن يمكن تحويله إلى طلبية.";
}

export function QuotesClient({
  canAdd = {},
  companyId,
  currency,
  initialQuotes,
  initialStats,
  totalCount,
  page,
  pageSize,
  searchQuery,
  statusFilter,
  traders,
  products,
  canCreate,
  canUpdate,
  initialError,
}: {
  companyId: string;
  currency: string;

  initialQuotes: QuoteRow[];

  initialStats: QuotesStats;

  totalCount: number;
  page: number;
  pageSize: number;

  searchQuery: string;

  statusFilter: QuoteStatusFilter;

  traders: QuoteTrader[];

  products: QuoteProduct[];

  canCreate: boolean;
  canUpdate: boolean;

  initialError: string | null;
  canAdd?: { trader?: boolean; supplier?: boolean; product?: boolean };
}) {
  const [supabase] = useState(() => createClient());
  const quick = useQuickCreate(supabase, companyId);
  const ownerPin = useOwnerPin(supabase, companyId);

  const traderOptions = useMemo(
    () => traders.map((row) => ({ id: row.id, label: row.name, hint: row.area })),
    [traders],
  );
  const productOptions = useMemo(() => products.map((row) => productOption(row)), [products]);
  const findTraders = useMemo(
    () => (term: string) => searchTraders(supabase, companyId, term),
    [supabase, companyId],
  );
  const findProducts = useMemo(
    () => (term: string) => searchProducts(supabase, companyId, term),
    [supabase, companyId],
  );

  const router = useRouter();

  const searchParams = useSearchParams();

  const [quotes, setQuotes] = useState(initialQuotes);

  const [notice, setNotice] = useState<Notice | null>(
    initialError
      ? {
          type: "error",
          text: initialError,
        }
      : null,
  );

  const [search, setSearch] = useState(searchQuery);

  const [filter, setFilter] = useState<QuoteStatusFilter>(statusFilter);

  const [createOpen, setCreateOpen] = useState(false);

  const [selected, setSelected] = useState<QuoteRow | null>(null);

  const [lifecycleTarget, setLifecycleTarget] = useState<{
    row: QuoteRow;
    action: LifecycleAction;
  } | null>(null);

  const [lifecycleMessage, setLifecycleMessage] = useState("");

  const [convertTarget, setConvertTarget] = useState<QuoteRow | null>(null);

  const [convertMessage, setConvertMessage] = useState("");

  const [trader, setTrader] = useState("");

  const [validUntil, setValidUntil] = useState(businessDateInput(7));

  const [notes, setNotes] = useState("");

  const [items, setItems] = useState<DraftItem[]>([emptyItem()]);

  const [createMessage, setCreateMessage] = useState("");

  const [saving, setSaving] = useState(false);

  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    setQuotes(initialQuotes);
  }, [initialQuotes]);

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

  const draftTotal = useMemo(
    () =>
      items.reduce((sum, item) => {
        const quantity = numberValue(item.quantity);

        const price = numberValue(item.sale_unit_price);

        return sum + quantity * price;
      }, 0),
    [items],
  );

  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));

  function navigate(nextSearch: string, nextFilter: QuoteStatusFilter, nextPage = 1) {
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

    router.push(query ? `/quotes?${query}` : "/quotes");
  }

  function startAdd() {
    if (!canCreate) {
      return;
    }

    setTrader("");
    setValidUntil(businessDateInput(7));
    setNotes("");
    setItems([emptyItem()]);
    setCreateMessage("");
    setCreateOpen(true);
  }

  function chooseProduct(index: number, productId: string, picked?: ProductPick) {
    const product = products.find((row) => row.id === productId) ?? picked;

    setItems((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index
          ? {
              ...item,
              product_id: productId,

              sale_unit_price: product?.sale_price != null ? String(product.sale_price) : "",
              mode: "base" as UnitMode,
              unit: product?.unit ?? null,
              pack_size: product?.pack_size ?? null,
              pack_unit: product?.pack_unit ?? null,
            }
          : item,
      ),
    );

    if (trader && productId) {
      void applyTraderPrices(
        trader,
        items.map((item, itemIndex) =>
          itemIndex === index ? { ...item, product_id: productId } : item,
        ),
        index,
      );
    }
  }

  // السطر بيتسعّر حسب مستوى سعر الزبون (جملة/مفرق...) إذا إلو مستوى.
  async function applyTraderPrices(traderId: string, lines: DraftItem[], onlyIndex?: number) {
    const ids = lines
      .filter(
        (line, lineIndex) =>
          line.product_id && (onlyIndex === undefined || lineIndex === onlyIndex),
      )
      .map((line) => line.product_id);
    const prices = await traderPrices(supabase, companyId, traderId, ids);
    if (!prices.size) return;
    setItems((current) =>
      current.map((line, lineIndex) => {
        if (onlyIndex !== undefined && lineIndex !== onlyIndex) return line;
        const base = prices.get(line.product_id);
        if (base == null) return line;
        return {
          ...line,
          sale_unit_price: convertPrice(String(base), "base", line.mode ?? "base", line.pack_size),
        };
      }),
    );
  }

  function changeUnit(index: number, mode: UnitMode) {
    setItems((current) =>
      current.map((line, lineIndex) =>
        lineIndex === index
          ? {
              ...line,
              mode,
              sale_unit_price: convertPrice(line.sale_unit_price, line.mode, mode, line.pack_size),
            }
          : line,
      ),
    );
  }

  function updateItem(index: number, changes: Partial<DraftItem>) {
    setItems((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index
          ? {
              ...item,
              ...changes,
            }
          : item,
      ),
    );
  }

  async function createQuote(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!canCreate || saving) {
      return;
    }

    setCreateMessage("");

    if (!trader) {
      setCreateMessage("اختر العميل.");
      return;
    }

    if (validUntil && validUntil < businessDateInput()) {
      setCreateMessage("تاريخ صلاحية العرض لا يمكن أن يكون بالماضي.");
      return;
    }

    if (!items.length) {
      setCreateMessage("أضف صنفاً واحداً على الأقل.");
      return;
    }

    const productIds = items.map((item) => item.product_id).filter(Boolean);

    if (new Set(productIds).size !== productIds.length) {
      setCreateMessage("لا يمكن إضافة نفس الصنف أكثر من مرة.");
      return;
    }

    for (const item of items) {
      const quantity = Number(item.quantity);

      const price = Number(item.sale_unit_price);

      if (
        !item.product_id ||
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        !Number.isFinite(price) ||
        price < 0
      ) {
        setCreateMessage("راجع الأصناف والكميات والأسعار.");
        return;
      }
    }

    setSaving(true);

    try {
      const { error } = await supabase.rpc("create_sales_quote", {
        target_company: companyId,

        target_trader: trader,

        target_valid_until: validUntil || null,

        target_notes: notes.trim() || null,

        items_payload: items.map((item) => ({
          product_id: item.product_id,

          quantity: toBaseQuantity(Number(item.quantity), item.mode, item.pack_size),

          sale_unit_price: toBasePrice(Number(item.sale_unit_price), item.mode, item.pack_size),
        })),
      });

      if (error) {
        setCreateMessage(friendlyError(error, "create"));
        return;
      }

      setCreateOpen(false);

      setNotice({
        type: "success",
        text: "تم إنشاء عرض السعر بنجاح.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  function openLifecycle(row: QuoteRow, action: LifecycleAction) {
    if (!canUpdate) {
      return;
    }

    if (action === "accepted" && row.expired) {
      setNotice({
        type: "error",
        text: "انتهت صلاحية عرض السعر ولا يمكن قبوله.",
      });
      return;
    }

    setLifecycleMessage("");

    setLifecycleTarget({
      row,
      action,
    });
  }

  async function saveLifecycle(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!lifecycleTarget || !canUpdate) {
      return;
    }

    const { row, action } = lifecycleTarget;

    setBusyId(row.id);

    setLifecycleMessage("");

    try {
      const { error } = await supabase.rpc("set_sales_quote_status", {
        target_company: companyId,

        target_quote: row.id,

        target_status: action,
      });

      if (error) {
        setLifecycleMessage(friendlyError(error, "status"));
        return;
      }

      setQuotes((current) =>
        current.map((quote) =>
          quote.id === row.id
            ? {
                ...quote,
                status: action,
                accepted_at: action === "accepted" ? new Date().toISOString() : quote.accepted_at,
              }
            : quote,
        ),
      );

      setSelected((current) =>
        current?.id === row.id
          ? {
              ...current,
              status: action,
              accepted_at: action === "accepted" ? new Date().toISOString() : current.accepted_at,
            }
          : current,
      );

      setLifecycleTarget(null);

      setNotice({
        type: "success",
        text: "تم تحديث حالة عرض السعر.",
      });

      router.refresh();
    } finally {
      setBusyId(null);
    }
  }

  function openConvert(row: QuoteRow) {
    if (!canCreate) {
      return;
    }

    if (row.expired) {
      setNotice({
        type: "error",
        text: "انتهت صلاحية عرض السعر ولا يمكن تحويله إلى طلبية.",
      });
      return;
    }

    setConvertMessage("");

    setConvertTarget(row);
  }

  async function saveConvert(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!convertTarget || !canCreate) {
      return;
    }

    setBusyId(convertTarget.id);

    setConvertMessage("");

    try {
      const { data, error } = await supabase.rpc("convert_sales_quote_to_order", {
        target_company: companyId,

        target_quote: convertTarget.id,
      });

      if (error) {
        setConvertMessage(friendlyError(error, "convert"));
        return;
      }

      const result = data as {
        status?: string;
        order_id?: string | null;
        approval_id?: string | null;
      } | null;

      if (result?.status === "pending_approval") {
        setConvertTarget(null);

        const approved =
          result.approval_id &&
          (await approveWithOwnerPin(supabase, companyId, ownerPin.ask, result.approval_id));

        setNotice({
          type: "success",
          text: approved
            ? "تمت موافقة المالك وتحوّل العرض لطلبية."
            : "السعر يحتاج موافقة. تم إنشاء طلب موافقة تلقائياً.",
        });

        router.refresh();
        return;
      }

      if (result?.order_id) {
        setConvertTarget(null);

        router.push(`/orders?order=${result.order_id}`);

        router.refresh();
        return;
      }

      setConvertMessage("لم يتم إنشاء الطلبية. حدّث الصفحة وحاول مرة ثانية.");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="page">
      {quick.modal}
      {ownerPin.modal}
      <div className="pageTitle">
        <div>
          <span className="eyebrow">عروض الأسعار</span>

          <h2>عروض الأسعار</h2>

          <p className="muted">أنشئ العرض، تابع حالته وحوّله لطلبية بدون إعادة إدخال الأصناف.</p>
        </div>

        {canCreate ? (
          <button type="button" className="primaryButton" onClick={startAdd}>
            <Icons.plus size={15} />
            عرض سعر جديد
          </button>
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
        <Mini title="كل العروض" value={formatQty(initialStats.allCount)} />

        <Mini title="مفتوحة" value={formatQty(initialStats.openCount)} />

        <Mini title="مقبولة" value={formatQty(initialStats.acceptedCount)} />

        <Mini title="تحولت لطلب" value={formatQty(initialStats.convertedCount)} />

        <Mini title="منتهية" value={formatQty(initialStats.expiredOpenCount)} />
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
              placeholder="رقم العرض، العميل، الصنف أو المبلغ..."
              aria-label="بحث في عروض الأسعار"
            />

            <button type="submit" className="softButton">
              بحث
            </button>
          </div>

          <select
            value={filter}
            aria-label="حالة عرض السعر"
            onChange={(event) => {
              const value = event.target.value as QuoteStatusFilter;

              setFilter(value);

              navigate(search, value, 1);
            }}
          >
            <option value="all">كل الحالات</option>

            <option value="draft">مسودة</option>

            <option value="sent">مرسل</option>

            <option value="accepted">مقبول</option>

            <option value="rejected">مرفوض</option>

            <option value="cancelled">ملغي</option>

            <option value="converted">تحوّل لطلب</option>

            <option value="expired">منتهي الصلاحية</option>
          </select>

          <div />

          <div className="resultCount">{formatQty(totalCount)} نتيجة</div>
        </form>

        {!quotes.length ? (
          <div className="empty">
            <Icons.money size={28} />

            <h3>لا توجد عروض أسعار</h3>

            <p>غيّر البحث أو الفلتر، أو أنشئ عرض سعر جديد.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الرقم</th>
                  <th>العميل</th>
                  <th>التاريخ</th>
                  <th>الصلاحية</th>
                  <th>الإجمالي</th>
                  <th>الحالة</th>
                  <th>الإجراءات</th>
                </tr>
              </thead>

              <tbody>
                {quotes.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.quote_number}</strong>
                    </td>

                    <td>
                      <strong>{row.trader?.name || "—"}</strong>
                      {row.source === "catalog" ? (
                        <span className="chip blue" style={{ marginInlineStart: 6 }}>
                          من الكتالوج
                        </span>
                      ) : null}

                      <span
                        className="muted"
                        style={{
                          display: "block",
                        }}
                      >
                        {row.trader?.area || ""}
                      </span>
                    </td>

                    <td>{formatDate(row.quote_date)}</td>

                    <td>
                      {row.valid_until || "بدون"}

                      {row.expired ? (
                        <span
                          className="chip orange"
                          style={{
                            marginInlineStart: 6,
                          }}
                        >
                          منتهي
                        </span>
                      ) : null}
                    </td>

                    <td>
                      <strong>{money(row.total, row.currency || currency)}</strong>
                    </td>

                    <td>
                      <span className={`chip ${statusColor(row.status)}`}>
                        {statusLabels[row.status]}
                      </span>
                    </td>

                    <td>
                      <div className="rowActions">
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => setSelected(row)}
                        >
                          تفاصيل
                        </button>

                        <Link className="softButton" href={`/print/quote/${row.id}`}>
                          طباعة / واتساب
                        </Link>

                        {canUpdate && row.status === "draft" ? (
                          <>
                            <button
                              type="button"
                              className="softButton"
                              disabled={busyId === row.id}
                              onClick={() => openLifecycle(row, "sent")}
                            >
                              إرسال
                            </button>

                            <button
                              type="button"
                              className="dangerButton"
                              disabled={busyId === row.id}
                              onClick={() => openLifecycle(row, "cancelled")}
                            >
                              إلغاء
                            </button>
                          </>
                        ) : null}

                        {canUpdate && row.status === "sent" ? (
                          <>
                            {!row.expired ? (
                              <button
                                type="button"
                                className="primaryButton"
                                disabled={busyId === row.id}
                                onClick={() => openLifecycle(row, "accepted")}
                              >
                                قبول
                              </button>
                            ) : null}

                            <button
                              type="button"
                              className="softButton"
                              disabled={busyId === row.id}
                              onClick={() => openLifecycle(row, "rejected")}
                            >
                              رفض
                            </button>

                            <button
                              type="button"
                              className="dangerButton"
                              disabled={busyId === row.id}
                              onClick={() => openLifecycle(row, "cancelled")}
                            >
                              إلغاء
                            </button>
                          </>
                        ) : null}

                        {canCreate && row.status === "accepted" && !row.expired ? (
                          <button
                            type="button"
                            className="primaryButton"
                            disabled={busyId === row.id}
                            onClick={() => openConvert(row)}
                          >
                            تحويل لطلب
                          </button>
                        ) : null}

                        {canUpdate && row.status === "accepted" ? (
                          <button
                            type="button"
                            className="dangerButton"
                            disabled={busyId === row.id}
                            onClick={() => openLifecycle(row, "cancelled")}
                          >
                            إلغاء
                          </button>
                        ) : null}

                        {row.converted_order_id ? (
                          <Link
                            className="softButton"
                            href={`/orders?order=${row.converted_order_id}`}
                          >
                            الطلبية
                          </Link>
                        ) : null}
                      </div>
                    </td>
                  </tr>
                ))}
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

      {createOpen ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              width: "94vw",
              maxWidth: 920,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">عرض جديد</span>

                <h2>إنشاء عرض سعر</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setCreateOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={createQuote}>
              <div className="formGrid">
                <label className="field">
                  <span>العميل</span>

                  <SearchPicker
                    value={trader}
                    placeholder="اكتب اسم العميل أو رقمو..."
                    options={traderOptions}
                    onSearch={findTraders}
                    onCreate={canAdd.trader ? (term) => quick.create("trader", term) : undefined}
                    createLabel="زبون"
                    onChange={(id) => {
                      setTrader(id);
                      if (id) void applyTraderPrices(id, items);
                    }}
                  />
                </label>

                <label className="field">
                  <span>صالح لغاية</span>

                  <input
                    type="date"
                    min={businessDateInput()}
                    value={validUntil}
                    onChange={(event) => setValidUntil(event.target.value)}
                  />
                </label>
              </div>

              <section
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                <div className="panelHeader">
                  <div>
                    <h2>الأصناف</h2>

                    <p>حدّد الكمية وسعر البيع لكل صنف.</p>
                  </div>

                  <button
                    type="button"
                    className="softButton"
                    onClick={() => setItems((current) => [...current, emptyItem()])}
                  >
                    <Icons.plus size={13} />
                    صنف
                  </button>
                </div>

                <div className="tableWrap">
                  <table className="dataTable">
                    <thead>
                      <tr>
                        <th>الصنف</th>
                        <th>الكمية</th>
                        <th>السعر</th>
                        <th>الإجمالي</th>
                        <th />
                      </tr>
                    </thead>

                    <tbody>
                      {items.map((item, index) => {
                        const total =
                          numberValue(item.quantity) * numberValue(item.sale_unit_price);

                        return (
                          <tr key={item.key}>
                            <td>
                              <SearchPicker
                                value={item.product_id}
                                placeholder="اسم الصنف أو كودو..."
                                options={productOptions}
                                onSearch={findProducts}
                                onCreate={canAdd.product ? (term) => quick.create("product", term) : undefined}
                                createLabel="صنف"
                                onChange={(id, option) =>
                                  chooseProduct(index, id, option?.data as ProductPick | undefined)
                                }
                              />
                            </td>

                            <td>
                              <NumberInput
                                min="0.001"
                                step="0.001"
                                value={item.quantity}
                                onChange={(event) =>
                                  updateItem(index, {
                                    quantity: event.target.value,
                                  })
                                }
                                style={{
                                  width: 105,
                                }}
                              />

                              <UnitToggle
                                mode={item.mode}
                                unit={item.unit}
                                packUnit={item.pack_unit}
                                packSize={item.pack_size}
                                quantity={item.quantity}
                                onChange={(mode) => changeUnit(index, mode)}
                              />
                            </td>

                            <td>
                              <NumberInput
                                min="0"
                                step="0.01"
                                value={item.sale_unit_price}
                                onChange={(event) =>
                                  updateItem(index, {
                                    sale_unit_price: event.target.value,
                                  })
                                }
                                style={{
                                  width: 120,
                                }}
                              />
                            </td>

                            <td>{money(total, currency)}</td>

                            <td>
                              <button
                                type="button"
                                className="dangerButton"
                                disabled={items.length === 1}
                                onClick={() =>
                                  setItems((current) =>
                                    current.filter((_, itemIndex) => itemIndex !== index),
                                  )
                                }
                              >
                                حذف
                              </button>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>

                <div
                  style={{
                    marginTop: 12,
                    textAlign: "end",
                  }}
                >
                  <strong>الإجمالي: {money(draftTotal, currency)}</strong>
                </div>
              </section>

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>ملاحظات</span>

                <textarea
                  value={notes}
                  onChange={(event) => setNotes(event.target.value)}
                  placeholder="اختياري"
                />
              </label>

              {createMessage ? (
                <div className="toastError" role="alert">
                  {createMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setCreateOpen(false)}
                >
                  إلغاء
                </button>

                <button type="submit" className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الإنشاء..." : "إنشاء العرض"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {selected ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              width: "94vw",
              maxWidth: 850,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">تفاصيل العرض</span>

                <h2>{selected.quote_number}</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setSelected(null)}>
                ×
              </button>
            </div>

            <div className="formGrid">
              <div className="field">
                <span>العميل</span>

                <strong>{selected.trader?.name || "—"}</strong>
              </div>

              <div className="field">
                <span>الحالة</span>

                <strong>{statusLabels[selected.status]}</strong>
              </div>

              <div className="field">
                <span>تاريخ العرض</span>

                <strong>{formatDate(selected.quote_date)}</strong>
              </div>

              <div className="field">
                <span>صالح لغاية</span>

                <strong>{selected.valid_until || "بدون"}</strong>
              </div>
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
                    <th>الكمية</th>
                    <th>السعر</th>
                    <th>الإجمالي</th>
                  </tr>
                </thead>

                <tbody>
                  {selected.items.map((item) => (
                    <tr key={item.id}>
                      <td>
                        <strong>{item.product_name}</strong>

                        <div className="muted">{item.sku || item.unit || ""}</div>
                      </td>

                      <td>
                        {new Intl.NumberFormat("en-US", { maximumFractionDigits: 3 }).format(
                          numberValue(item.quantity),
                        )}
                      </td>

                      <td>{money(item.sale_unit_price, selected.currency)}</td>

                      <td>{money(item.line_total, selected.currency)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {selected.notes ? (
              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                <strong>ملاحظات</strong>

                <p className="muted">{selected.notes}</p>
              </div>
            ) : null}

            <div className="modalActions">
              <strong>الإجمالي: {money(selected.total, selected.currency)}</strong>

              <button type="button" className="softButton" onClick={() => setSelected(null)}>
                إغلاق
              </button>
            </div>
          </section>
        </div>
      ) : null}

      {lifecycleTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">حالة العرض</span>

                <h2>{lifecycleTitle(lifecycleTarget.action)}</h2>
              </div>
            </div>

            <form onSubmit={saveLifecycle}>
              <p>
                العرض: <strong>{lifecycleTarget.row.quote_number}</strong>
              </p>

              <p className="muted">{lifecycleDescription(lifecycleTarget.action)}</p>

              {lifecycleMessage ? (
                <div className="toastError" role="alert">
                  {lifecycleMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={busyId === lifecycleTarget.row.id}
                  onClick={() => setLifecycleTarget(null)}
                >
                  رجوع
                </button>

                <button
                  type="submit"
                  className={
                    lifecycleTarget.action === "cancelled" || lifecycleTarget.action === "rejected"
                      ? "dangerButton"
                      : "primaryButton"
                  }
                  disabled={busyId === lifecycleTarget.row.id}
                >
                  {busyId === lifecycleTarget.row.id ? "جارٍ الحفظ..." : "تأكيد"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {convertTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">تحويل العرض</span>

                <h2>إنشاء طلبية من عرض السعر</h2>
              </div>
            </div>

            <form onSubmit={saveConvert}>
              <p>
                العرض: <strong>{convertTarget.quote_number}</strong>
              </p>

              <p className="muted">
                سيتم إنشاء الطلبية بنفس العميل والأصناف والكميات والأسعار الموجودة في العرض. إذا كان
                أي سعر تحت الحد المسموح فسيتم إنشاء طلب موافقة بدلاً من تجاوز الحماية.
              </p>

              {convertMessage ? (
                <div className="toastError" role="alert">
                  {convertMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={busyId === convertTarget.id}
                  onClick={() => setConvertTarget(null)}
                >
                  رجوع
                </button>

                <button
                  type="submit"
                  className="primaryButton"
                  disabled={busyId === convertTarget.id}
                >
                  {busyId === convertTarget.id ? "جارٍ التحويل..." : "تأكيد التحويل"}
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
