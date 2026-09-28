"use client";

import Link from "next/link";

import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { Icons } from "@/components/icons";
import { OrderDetails } from "@/components/orders/order-details";
import { SearchPicker } from "@/components/search-picker";
import { UnitToggle } from "@/components/unit-toggle";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import {
  convertPrice,
  toBasePrice,
  toBaseQuantity,
  traderPrices,
  type UnitMode,
} from "@/lib/units";
import { productOption, searchProducts, searchTraders, type ProductPick } from "@/lib/pickers";
import { createClient } from "@/lib/supabase/client";

type OrderStatus =
  | "draft"
  | "new"
  | "to_purchase"
  | "purchasing"
  | "ready"
  | "out_for_delivery"
  | "delivered"
  | "cancelled";

export type OrderFilter = "all" | OrderStatus;

type PaymentStatus = "unpaid" | "partial" | "paid" | "credit";

type PaymentMethod = "cash" | "bank" | "card" | "check" | "other";

export type OrderTrader = {
  id: string;
  name: string;
  area: string | null;
  status: string;
};

export type OrderProduct = {
  id: string;
  name: string;
  sku: string | null;
  sale_price: number | null;
  minimum_sale_price: number | null;
  unit: string;
  active: boolean;
  pack_size?: number | null;
  pack_unit?: string | null;
};

export type OrderSalesInvoice = {
  id: string;
  order_id: string;
  trader_id: string;
  invoice_number: string;
  invoice_date: string;
  currency: string;
  total: number;
  paid_total: number;
  balance_due: number;
  payment_status: "unpaid" | "partial" | "paid";
  status: "posted" | "cancelled";
};

export type OrderCashbox = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
};

export type OrderStats = {
  total: number;
  active: number;
  new: number;
  ready: number;
  totalValue: number;
};

type TraderRelation = {
  name: string;
  area: string | null;
  phone: string | null;
  whatsapp: string | null;
};

type ProductRelation = {
  name: string;
  sku: string | null;
};

type OrderItem = {
  id: string;
  product_id: string;
  quantity: number;
  sale_unit_price: number;
  line_total: number;
  products: ProductRelation | ProductRelation[] | null;
};

export type OrderRow = {
  id: string;
  order_number: string | null;
  trader_id: string;
  status: OrderStatus;
  payment_status: PaymentStatus;
  subtotal: number;
  total: number;
  notes: string | null;
  created_at: string;
  delivered_at: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  traders: TraderRelation | TraderRelation[] | null;
  sales_order_items: OrderItem[];
};

type ItemDraft = {
  product_id: string;
  quantity: string;
  sale_unit_price: string;
  mode?: UnitMode;
  unit?: string | null;
  pack_size?: number | null;
  pack_unit?: string | null;
};

type CollectionState = {
  order: OrderRow;
  invoices: OrderSalesInvoice[];
};

type Notice = {
  type: "error" | "success";
  text: string;
};

const statusLabels: Record<OrderStatus, string> = {
  draft: "مسودة",
  new: "جديد",
  to_purchase: "بانتظار التوفير",
  purchasing: "قيد التوفير",
  ready: "جاهز",
  out_for_delivery: "بالتوصيل",
  delivered: "تم التسليم",
  cancelled: "ملغي",
};

const paymentLabels: Record<PaymentStatus, string> = {
  unpaid: "غير مدفوع",
  partial: "مدفوع جزئياً",
  paid: "مدفوع",
  credit: "آجل",
};

const paymentMethodLabels: Record<PaymentMethod, string> = {
  cash: "نقدي",
  bank: "تحويل بنكي",
  card: "بطاقة",
  check: "شيك",
  other: "أخرى",
};

function emptyItem(): ItemDraft {
  return {
    product_id: "",
    quantity: "1",
    sale_unit_price: "",
  };
}

function oneRelation<T>(value: T | T[] | null) {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function businessDateInput() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());

  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";

  return `${get("year")}-${get("month")}-${get("day")}`;
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("ar-SY", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

function money(value: number, currency: string) {
  return `${new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Number(value || 0))} ${currency}`;
}

function friendlyError(
  error: {
    code?: string;
    message?: string;
  } | null,
  action: "create" | "cancel" | "payment" | "quote",
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

  if (message.includes("duplicate products")) {
    return "لا يمكن تكرار نفس الصنف داخل الطلبية.";
  }

  if (message.includes("invalid trader")) {
    return "العميل غير صالح أو مؤرشف.";
  }

  if (message.includes("inactive product") || message.includes("invalid product")) {
    return "أحد الأصناف غير صالح أو مؤرشف.";
  }

  if (message.includes("credit") || raw.includes("ائتمان")) {
    return "لا يمكن إنشاء الطلبية لأن حد ائتمان العميل لا يسمح بهذه العملية.";
  }

  if (message.includes("cancel sales invoice first")) {
    return "يجب إلغاء فاتورة البيع المرتبطة أولاً.";
  }

  if (message.includes("cannot be cancelled")) {
    return "لا يمكن إلغاء الطلبية بعد بدء التوصيل أو التسليم.";
  }

  if (message.includes("cancellation reason")) {
    return "سبب الإلغاء مطلوب.";
  }

  if (message.includes("exchange") || message.includes("currency") || message.includes("rate")) {
    return "تعذر احتساب سعر الصرف لهذه العملية. تحقق من أسعار الصرف والتاريخ.";
  }

  if (action === "cancel") {
    return "تعذر إلغاء الطلبية. حاول مرة ثانية.";
  }

  if (action === "payment") {
    return "تعذر تسجيل القبض. تحقق من البيانات وحاول مرة ثانية.";
  }

  if (action === "quote") {
    return "تعذر احتساب مبلغ القبض بعملة الصندوق.";
  }

  return "تعذر إنشاء الطلبية. تحقق من البيانات وحاول مرة ثانية.";
}

export function OrdersClient({
  companyId,
  currency,
  initialOrders,
  traders,
  products,
  invoices,
  cashboxes,
  initialStats,
  initialError,
  totalCount,
  page,
  pageSize,
  searchQuery,
  statusFilter,
  focusedOrderId,
  canCreate,
  canCancel,
  canCollect,
  canViewDeliveries,
  canCancelInvoice,
  canReversePayment,
}: {
  companyId: string;
  currency: string;
  initialOrders: OrderRow[];
  traders: OrderTrader[];
  products: OrderProduct[];
  invoices: OrderSalesInvoice[];
  cashboxes: OrderCashbox[];
  initialStats: OrderStats | null;
  initialError: string | null;
  totalCount: number;
  page: number;
  pageSize: number;
  searchQuery: string;
  statusFilter: OrderFilter;
  focusedOrderId: string | null;
  canCreate: boolean;
  canCancel: boolean;
  canCollect: boolean;
  canViewDeliveries: boolean;
  canCancelInvoice: boolean;
  canReversePayment: boolean;
}) {
  const [supabase] = useState(() => createClient());

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

  const [orders, setOrders] = useState(initialOrders);

  const [search, setSearch] = useState(searchQuery);

  const [filter, setFilter] = useState<OrderFilter>(statusFilter);

  const [notice, setNotice] = useState<Notice | null>(
    initialError
      ? {
          type: "error",
          text: initialError,
        }
      : null,
  );

  const [open, setOpen] = useState(false);

  const [trader, setTrader] = useState("");

  const [items, setItems] = useState<ItemDraft[]>([emptyItem()]);

  const [notes, setNotes] = useState("");

  const [saving, setSaving] = useState(false);

  const [message, setMessage] = useState("");

  const [cancelTarget, setCancelTarget] = useState<OrderRow | null>(null);

  const [cancelReason, setCancelReason] = useState("");

  const [cancelMessage, setCancelMessage] = useState("");

  const [cancelling, setCancelling] = useState(false);

  const [collection, setCollection] = useState<CollectionState | null>(null);

  const [paymentAmount, setPaymentAmount] = useState("");

  const [paymentCashAmount, setPaymentCashAmount] = useState("");

  const [paymentCashCurrency, setPaymentCashCurrency] = useState(currency);

  const [paymentInvoiceCurrency, setPaymentInvoiceCurrency] = useState(currency);

  const [paymentFxRate, setPaymentFxRate] = useState<number | null>(1);
  // سعر الصرف لحظة القبض (1 دولار = كم ليرة) — بيكتبو الموظف.
  const [txRate, setTxRate] = useState("");

  const [paymentQuoteError, setPaymentQuoteError] = useState("");

  const [quoteLoading, setQuoteLoading] = useState(false);

  const [paymentDate, setPaymentDate] = useState(businessDateInput());

  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("cash");

  const [paymentCashbox, setPaymentCashbox] = useState("");

  const [paymentReference, setPaymentReference] = useState("");

  const [paymentNotes, setPaymentNotes] = useState("");

  const [paymentMessage, setPaymentMessage] = useState("");

  const [collecting, setCollecting] = useState(false);

  const [detailsOrder, setDetailsOrder] = useState<OrderRow | null>(null);

  useEffect(() => {
    setOrders(initialOrders);
  }, [initialOrders]);

  useEffect(() => {
    setSearch(searchQuery);
  }, [searchQuery]);

  useEffect(() => {
    setFilter(statusFilter);
  }, [statusFilter]);

  useEffect(() => {
    if (initialError) {
      setNotice({
        type: "error",
        text: initialError,
      });
    }
  }, [initialError]);

  const highlighted = searchParams.get("order");

  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));

  const visibleFrom = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;

  const visibleTo = Math.min(page * pageSize, totalCount);

  const invoicesByOrder = useMemo(() => {
    const map = new Map<string, OrderSalesInvoice[]>();

    for (const invoice of invoices) {
      const rows = map.get(invoice.order_id) ?? [];

      rows.push(invoice);

      map.set(invoice.order_id, rows);
    }

    for (const rows of map.values()) {
      rows.sort((a, b) => a.invoice_date.localeCompare(b.invoice_date));
    }

    return map;
  }, [invoices]);

  const orderTotal = useMemo(
    () =>
      items.reduce(
        (sum, item) => sum + Number(item.quantity || 0) * Number(item.sale_unit_price || 0),
        0,
      ),
    [items],
  );

  const collectionTotal = collection
    ? collection.invoices.reduce((sum, invoice) => sum + Number(invoice.total || 0), 0)
    : 0;

  const collectionPaid = collection
    ? collection.invoices.reduce((sum, invoice) => sum + Number(invoice.paid_total || 0), 0)
    : 0;

  const collectionBalance = collection
    ? collection.invoices.reduce((sum, invoice) => sum + Number(invoice.balance_due || 0), 0)
    : 0;

  function navigate(nextSearch: string, nextFilter: OrderFilter, nextPage = 1) {
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

    router.push(query ? `/orders?${query}` : "/orders");
  }

  function submitSearch(event: FormEvent) {
    event.preventDefault();

    navigate(search, filter, 1);
  }

  function resetForm() {
    setTrader("");
    setItems([emptyItem()]);
    setNotes("");
    setMessage("");
  }

  function startAdd() {
    if (!canCreate) {
      return;
    }

    resetForm();
    setOpen(true);
  }

  function chooseProduct(index: number, productId: string, picked?: ProductPick) {
    const product = products.find((row) => row.id === productId) ?? picked;

    setItems((current) =>
      current.map((item, currentIndex) =>
        currentIndex === index
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
  async function applyTraderPrices(traderId: string, lines: ItemDraft[], onlyIndex?: number) {
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

  function updateItem(index: number, changes: Partial<ItemDraft>) {
    setItems((current) =>
      current.map((item, currentIndex) =>
        currentIndex === index
          ? {
              ...item,
              ...changes,
            }
          : item,
      ),
    );
  }

  async function createOrder(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");

    if (!canCreate) {
      setMessage("ما عندك صلاحية إنشاء طلبية.");
      return;
    }

    if (!trader) {
      setMessage("اختر العميل.");
      return;
    }

    const selectedIds = items.map((item) => item.product_id).filter(Boolean);

    if (new Set(selectedIds).size !== selectedIds.length) {
      setMessage("لا يمكن تكرار نفس الصنف داخل الطلبية.");
      return;
    }

    const invalid = items.some((item) => {
      const qty = Number(item.quantity);

      const price = Number(item.sale_unit_price);

      return (
        !item.product_id ||
        !Number.isFinite(qty) ||
        qty <= 0 ||
        !Number.isFinite(price) ||
        price < 0
      );
    });

    if (invalid) {
      setMessage("راجع الأصناف والكميات وأسعار البيع.");
      return;
    }

    // الكرتونة بتتحوّل لقطع قبل الحفظ (المخزون والفواتير بالقطعة).
    const payload = items.map((item) => ({
      product_id: item.product_id,
      quantity: toBaseQuantity(Number(item.quantity), item.mode, item.pack_size),
      sale_unit_price: toBasePrice(Number(item.sale_unit_price), item.mode, item.pack_size),
    }));

    setSaving(true);

    try {
      const { data, error } = await supabase.rpc("create_sales_order_v2", {
        target_company: companyId,
        target_trader: trader,
        target_notes: notes.trim() || null,
        items_payload: payload,
        target_source_quote: null,
      });

      if (error) {
        setMessage(friendlyError(error, "create"));
        return;
      }

      const result = data as {
        status?: string;
        order_id?: string | null;
        approval_id?: string | null;
      } | null;

      setOpen(false);
      resetForm();

      if (result?.status === "pending_approval") {
        setNotice({
          type: "success",
          text: "السعر يحتاج موافقة. تم إنشاء طلب الموافقة بنجاح ولم تُنشأ الطلبية بعد.",
        });
      } else {
        setNotice({
          type: "success",
          text: "تم إنشاء الطلبية بنجاح.",
        });
      }

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  function openCancel(order: OrderRow) {
    if (!canCancel) {
      return;
    }

    setCancelTarget(order);
    setCancelReason("");
    setCancelMessage("");
  }

  async function saveCancel(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!cancelTarget || !canCancel) {
      return;
    }

    const reason = cancelReason.trim();

    if (!reason) {
      setCancelMessage("اكتب سبب الإلغاء.");
      return;
    }

    setCancelling(true);
    setCancelMessage("");

    try {
      const { error } = await supabase.rpc("cancel_sales_order", {
        target_company: companyId,
        target_order: cancelTarget.id,
        target_reason: reason,
      });

      if (error) {
        setCancelMessage(friendlyError(error, "cancel"));
        return;
      }

      setOrders((current) =>
        current.map((order) =>
          order.id === cancelTarget.id
            ? {
                ...order,
                status: "cancelled",
                cancellation_reason: reason,
                cancelled_at: new Date().toISOString(),
              }
            : order,
        ),
      );

      setCancelTarget(null);
      setCancelReason("");

      setNotice({
        type: "success",
        text: "تم إلغاء الطلبية وتحرير حجز المخزون.",
      });

      router.refresh();
    } finally {
      setCancelling(false);
    }
  }

  function openCollection(order: OrderRow) {
    if (!canCollect) {
      return;
    }

    if (order.status === "cancelled") {
      setNotice({
        type: "error",
        text: "الطلبية ملغاة.",
      });
      return;
    }

    const orderInvoices = (invoicesByOrder.get(order.id) ?? []).filter(
      (invoice) => invoice.status === "posted" && Number(invoice.balance_due || 0) > 0,
    );

    if (!orderInvoices.length) {
      setNotice({
        type: "error",
        text: "لا توجد فاتورة مستحقة لهذه الطلبية.",
      });
      return;
    }

    const invoiceCurrency = orderInvoices[0].currency;

    if (orderInvoices.some((invoice) => invoice.currency !== invoiceCurrency)) {
      setNotice({
        type: "error",
        text: "فواتير الطلبية تحتوي على أكثر من عملة ولا يمكن قبضها بعملية واحدة.",
      });
      return;
    }

    const balance = orderInvoices.reduce(
      (sum, invoice) => sum + Number(invoice.balance_due || 0),
      0,
    );

    const matchingCashbox = cashboxes.find((cashbox) => cashbox.currency === invoiceCurrency);

    const firstCashbox = matchingCashbox ?? cashboxes[0];

    setCollection({
      order,
      invoices: orderInvoices,
    });

    setPaymentAmount(balance.toFixed(2));

    setPaymentDate(businessDateInput());

    setPaymentMethod("cash");

    setPaymentCashbox(firstCashbox?.id ?? "");

    setPaymentCashAmount(firstCashbox?.currency === invoiceCurrency ? balance.toFixed(2) : "");

    setPaymentCashCurrency(firstCashbox?.currency ?? invoiceCurrency);

    setPaymentInvoiceCurrency(invoiceCurrency);

    setPaymentFxRate(firstCashbox?.currency === invoiceCurrency ? 1 : null);

    setPaymentQuoteError("");
    setPaymentReference("");
    setPaymentNotes("");
    setPaymentMessage("");
  }

  useEffect(() => {
    let cancelled = false;

    async function refreshQuote() {
      if (!collection || !paymentCashbox || !paymentDate) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        setQuoteLoading(false);
        return;
      }

      const invoiceCurrency = collection.invoices[0]?.currency ?? currency;

      setPaymentInvoiceCurrency(invoiceCurrency);

      const selectedCashbox = cashboxes.find((cashbox) => cashbox.id === paymentCashbox);

      if (!selectedCashbox) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        setQuoteLoading(false);
        return;
      }

      setPaymentCashCurrency(selectedCashbox.currency);

      const invoiceAmount = Number(paymentAmount || 0);

      if (!Number.isFinite(invoiceAmount) || invoiceAmount <= 0) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        setQuoteLoading(false);
        return;
      }

      if (selectedCashbox.currency === invoiceCurrency) {
        setPaymentCashAmount(invoiceAmount.toFixed(2));
        setPaymentFxRate(1);
        setPaymentQuoteError("");
        setQuoteLoading(false);
        return;
      }

      // فاتورة بالدولار ومقبوضة بالليرة: المبلغ = الدولار × السعر اللي كتبو الموظف.
      if (invoiceCurrency === currency && Number(txRate) > 0) {
        setPaymentCashAmount((invoiceAmount * Number(txRate)).toFixed(2));
        setPaymentFxRate(1 / Number(txRate));
        setPaymentQuoteError("");
        setQuoteLoading(false);
        return;
      }

      setQuoteLoading(true);
      setPaymentCashAmount("");
      setPaymentFxRate(null);

      const { data, error } = await supabase.rpc("payment_currency_quote", {
        target_company: companyId,
        target_invoice_currency: invoiceCurrency,
        target_payment_currency: selectedCashbox.currency,
        target_invoice_amount: invoiceAmount,
        target_payment_date: paymentDate,
      });

      if (cancelled) {
        return;
      }

      setQuoteLoading(false);

      if (error) {
        setPaymentQuoteError(friendlyError(error, "quote"));
        return;
      }

      const quote = Array.isArray(data) ? data[0] : data;

      const quotedAmount = Number(quote?.payment_amount ?? 0);

      const quotedRate = Number(quote?.payment_rate_to_base ?? 0);

      if (
        !Number.isFinite(quotedAmount) ||
        quotedAmount <= 0 ||
        !Number.isFinite(quotedRate) ||
        quotedRate <= 0
      ) {
        setPaymentQuoteError("تعذر احتساب مبلغ القبض بعملة الصندوق.");
        return;
      }

      setPaymentCashAmount(quotedAmount.toFixed(2));

      setPaymentFxRate(quotedRate);

      setPaymentQuoteError("");
    }

    void refreshQuote();

    return () => {
      cancelled = true;
    };
  }, [
    txRate,
    collection,
    paymentCashbox,
    paymentDate,
    paymentAmount,
    cashboxes,
    companyId,
    currency,
    supabase,
  ]);

  async function saveCollection(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!collection || !canCollect) {
      return;
    }

    setPaymentMessage("");

    const amount = Number(paymentAmount);

    const balance = collection.invoices.reduce(
      (sum, invoice) => sum + Number(invoice.balance_due || 0),
      0,
    );

    if (!Number.isFinite(amount) || amount <= 0) {
      setPaymentMessage("اكتب مبلغ قبض صحيح.");
      return;
    }

    if (amount > balance + 0.01) {
      setPaymentMessage(`المبلغ أكبر من الرصيد المستحق ${money(balance, paymentInvoiceCurrency)}.`);
      return;
    }

    if (!paymentCashbox) {
      setPaymentMessage("اختر الصندوق.");
      return;
    }

    if (!paymentDate) {
      setPaymentMessage("اختر تاريخ القبض.");
      return;
    }

    const selectedCashbox = cashboxes.find((cashbox) => cashbox.id === paymentCashbox);

    if (!selectedCashbox) {
      setPaymentMessage("الصندوق المختار غير صالح.");
      return;
    }

    const invoiceCurrency = collection.invoices[0]?.currency ?? currency;

    let remaining = Number(amount.toFixed(2));

    const allocationsPayload: Array<{
      sales_invoice_id: string;
      amount: number;
    }> = [];

    for (const invoice of collection.invoices) {
      if (remaining <= 0) {
        break;
      }

      const invoiceBalance = Number(invoice.balance_due || 0);

      if (invoiceBalance <= 0) {
        continue;
      }

      const applied = Math.min(remaining, invoiceBalance);

      allocationsPayload.push({
        sales_invoice_id: invoice.id,
        amount: Number(applied.toFixed(2)),
      });

      remaining = Number((remaining - applied).toFixed(2));
    }

    if (!allocationsPayload.length) {
      setPaymentMessage("لا يوجد رصيد مستحق للقبض.");
      return;
    }

    setCollecting(true);

    try {
      let cashAmount = amount;

      if (selectedCashbox.currency !== invoiceCurrency) {
        const rateError = await applyTransactionRate(
          supabase,
          companyId,
          selectedCashbox.currency,
          currency,
          paymentDate,
          txRate,
        );

        if (rateError) {
          setPaymentMessage(rateError);
          return;
        }

        const { data, error } = await supabase.rpc("payment_currency_quote", {
          target_company: companyId,
          target_invoice_currency: invoiceCurrency,
          target_payment_currency: selectedCashbox.currency,
          target_invoice_amount: amount,
          target_payment_date: paymentDate,
        });

        if (error) {
          setPaymentMessage(friendlyError(error, "quote"));
          return;
        }

        const quote = Array.isArray(data) ? data[0] : data;

        const rate = Number(quote?.payment_rate_to_base ?? 0);

        if (!Number.isFinite(rate) || rate <= 0) {
          setPaymentMessage("تعذر تثبيت سعر الصرف لهذه العملية.");
          return;
        }

        cashAmount = allocationsPayload.reduce(
          (total, allocation) => total + Number((allocation.amount / rate).toFixed(2)),
          0,
        );

        cashAmount = Number(cashAmount.toFixed(2));
      }

      const { error } = await supabase.rpc("record_customer_payment", {
        target_company: companyId,
        target_trader: collection.order.trader_id,
        target_cashbox: paymentCashbox,
        target_amount: cashAmount,
        target_payment_date: paymentDate,
        target_method: paymentMethod,
        target_reference: paymentReference.trim() || null,
        target_notes: paymentNotes.trim() || null,
        allocations_payload: allocationsPayload,
      });

      if (error) {
        setPaymentMessage(friendlyError(error, "payment"));
        return;
      }

      setCollection(null);
      setPaymentAmount("");
      setPaymentCashAmount("");
      setPaymentQuoteError("");

      setNotice({
        type: "success",
        text: "تم تسجيل القبض بنجاح.",
      });

      router.refresh();
    } finally {
      setCollecting(false);
    }
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المبيعات</span>

          <h2>طلبيات العملاء</h2>

          <p className="muted">الطلبات، حالة التوفير، التسليم والتحصيل.</p>
        </div>

        {canCreate ? (
          <button type="button" className="primaryButton" onClick={startAdd}>
            <Icons.plus size={15} />
            طلبية جديدة
          </button>
        ) : null}
      </div>

      {notice ? (
        notice.type === "error" ? (
          <div
            className="toastError"
            role="alert"
            style={{
              marginBottom: 14,
            }}
          >
            {notice.text}
          </div>
        ) : (
          <div
            className="panel panelPad"
            role="status"
            aria-live="polite"
            style={{
              marginBottom: 14,
            }}
          >
            {notice.text}
          </div>
        )
      ) : null}

      {focusedOrderId ? (
        <div className="panel panelPad rowActions" style={{ marginBottom: 14 }}>
          <span>عم نعرض طلبية وحدة بس.</span>
          <Link className="softButton" href="/orders">
            عرض كل الطلبيات
          </Link>
        </div>
      ) : null}

      <section className="statsGrid">
        <Mini title="كل الطلبات" value={initialStats ? String(initialStats.total) : "—"} />

        <Mini title="الطلبات الفعالة" value={initialStats ? String(initialStats.active) : "—"} />

        <Mini title="جاهزة / بالتوصيل" value={initialStats ? String(initialStats.ready) : "—"} />

        <Mini
          title="قيمة الطلبات الفعالة"
          value={initialStats ? money(initialStats.totalValue, currency) : "—"}
        />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        <div className="filters">
          <form className="searchBox" onSubmit={submitSearch}>
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="ابحث باسم العميل..."
              aria-label="بحث في الطلبات"
            />

            <button type="submit" className="softButton">
              بحث
            </button>
          </form>

          <select
            value={filter}
            aria-label="تصفية الطلبات حسب الحالة"
            onChange={(event) => {
              const value = event.target.value as OrderFilter;

              setFilter(value);

              navigate(search, value, 1);
            }}
          >
            <option value="all">كل الحالات</option>
            <option value="new">جديد</option>
            <option value="to_purchase">بانتظار التوفير</option>
            <option value="purchasing">قيد التوفير</option>
            <option value="ready">جاهز</option>
            <option value="out_for_delivery">بالتوصيل</option>
            <option value="delivered">تم التسليم</option>
            <option value="cancelled">ملغي</option>
          </select>

          <div />

          <div className="resultCount">
            {totalCount === 0 ? "0 نتيجة" : `${visibleFrom}–${visibleTo} من ${totalCount}`}
          </div>
        </div>

        {!orders.length ? (
          <div className="empty">
            <Icons.box size={29} />

            <h3>لا توجد طلبات</h3>

            <p>غيّر البحث أو التصفية أو أنشئ طلبية جديدة.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الطلب</th>
                  <th>العميل</th>
                  <th>الأصناف</th>
                  <th>الحالة</th>
                  <th>الإجمالي</th>
                  <th>الدفع</th>
                  <th>الفاتورة</th>
                  <th>إجراءات</th>
                </tr>
              </thead>

              <tbody>
                {orders.map((order) => {
                  const traderRow = oneRelation(order.traders);

                  const orderInvoices = invoicesByOrder.get(order.id) ?? [];

                  const dueInvoices = orderInvoices.filter(
                    (invoice) => Number(invoice.balance_due || 0) > 0,
                  );

                  const outstandingBalance = dueInvoices.reduce(
                    (sum, invoice) => sum + Number(invoice.balance_due || 0),
                    0,
                  );

                  const firstInvoice = orderInvoices[0];

                  const invoiceCurrency =
                    dueInvoices[0]?.currency ?? firstInvoice?.currency ?? currency;

                  return (
                    <tr
                      key={order.id}
                      style={
                        highlighted === order.id
                          ? {
                              background: "rgba(42,201,156,.045)",
                            }
                          : undefined
                      }
                    >
                      <td>
                        <strong>{order.order_number ?? `#${order.id.slice(0, 8)}`}</strong>

                        <div className="muted">{formatDateTime(order.created_at)}</div>
                      </td>

                      <td>
                        <strong>{traderRow?.name || "—"}</strong>

                        {traderRow?.area ? <div className="muted">{traderRow.area}</div> : null}
                      </td>

                      <td>
                        <strong>{order.sales_order_items.length}</strong>
                      </td>

                      <td>
                        <span
                          className={`chip ${
                            ["ready", "delivered"].includes(order.status)
                              ? "green"
                              : order.status === "cancelled"
                                ? "gray"
                                : "orange"
                          }`}
                        >
                          {statusLabels[order.status]}
                        </span>
                      </td>

                      <td>{money(Number(order.total || 0), currency)}</td>

                      <td>{paymentLabels[order.payment_status]}</td>

                      <td>
                        {firstInvoice ? (
                          <div>
                            <strong>{firstInvoice.invoice_number}</strong>

                            <div className="muted">
                              {dueInvoices.length === 0
                                ? "مسددة"
                                : `متبقي ${money(outstandingBalance, invoiceCurrency)}`}
                            </div>
                          </div>
                        ) : (
                          "—"
                        )}
                      </td>

                      <td>
                        <div className="rowActions">
                          <button
                            type="button"
                            className="softButton"
                            onClick={() => setDetailsOrder(order)}
                          >
                            تفاصيل
                          </button>

                          {canViewDeliveries &&
                          ["ready", "out_for_delivery"].includes(order.status) ? (
                            <a className="softButton" href="/deliveries">
                              توصيل
                            </a>
                          ) : null}

                          {canCollect && order.status !== "cancelled" && dueInvoices.length > 0 ? (
                            <button
                              type="button"
                              className="primaryButton"
                              onClick={() => openCollection(order)}
                            >
                              قبض
                            </button>
                          ) : null}

                          {canCancel &&
                          !["out_for_delivery", "delivered", "cancelled"].includes(order.status) ? (
                            <button
                              type="button"
                              className="dangerButton"
                              onClick={() => openCancel(order)}
                            >
                              إلغاء
                            </button>
                          ) : null}
                        </div>
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
              onClick={() => navigate(searchQuery, statusFilter, Math.max(1, page - 1))}
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
              onClick={() => navigate(searchQuery, statusFilter, Math.min(pageCount, page + 1))}
            >
              التالي
            </button>
          </div>
        ) : null}
      </section>

      {open ? (
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
              <h2>طلبية جديدة</h2>

              <button type="button" className="closeButton" onClick={() => setOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={createOrder}>
              <label className="field">
                <span>العميل *</span>

                <SearchPicker
                  value={trader}
                  placeholder="اكتب اسم العميل أو رقمو..."
                  options={traderOptions}
                  onSearch={findTraders}
                  onChange={(id) => {
                    setTrader(id);
                    if (id) void applyTraderPrices(id, items);
                  }}
                />
              </label>

              <div className="quickList">
                {items.map((item, index) => (
                  <div className="quickItem" key={index}>
                    <SearchPicker
                      value={item.product_id}
                      placeholder="اسم الصنف أو كودو..."
                      options={productOptions}
                      onSearch={findProducts}
                      onChange={(id, option) =>
                        chooseProduct(index, id, option?.data as ProductPick | undefined)
                      }
                    />

                    <input
                      type="number"
                      min="0.001"
                      step="0.001"
                      value={item.quantity}
                      onChange={(event) =>
                        updateItem(index, {
                          quantity: event.target.value,
                        })
                      }
                    />

                    <UnitToggle
                      mode={item.mode}
                      unit={item.unit}
                      packUnit={item.pack_unit}
                      packSize={item.pack_size}
                      quantity={item.quantity}
                      onChange={(mode) => changeUnit(index, mode)}
                    />

                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={item.sale_unit_price}
                      onChange={(event) =>
                        updateItem(index, {
                          sale_unit_price: event.target.value,
                        })
                      }
                    />

                    <button
                      type="button"
                      className="dangerButton"
                      disabled={items.length === 1}
                      onClick={() =>
                        setItems((current) => current.filter((_, rowIndex) => rowIndex !== index))
                      }
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>

              <button
                type="button"
                className="softButton"
                onClick={() => setItems((current) => [...current, emptyItem()])}
              >
                إضافة صنف
              </button>

              <label className="field">
                <span>ملاحظات</span>

                <textarea value={notes} onChange={(event) => setNotes(event.target.value)} />
              </label>

              <div className="statValue">الإجمالي: {money(orderTotal, currency)}</div>

              {message ? <div className="toastError">{message}</div> : null}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الحفظ..." : "حفظ الطلبية"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {cancelTarget ? (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <h2>إلغاء الطلبية</h2>
            </div>

            <form onSubmit={saveCancel}>
              <label className="field">
                <span>سبب الإلغاء *</span>

                <textarea
                  value={cancelReason}
                  onChange={(event) => setCancelReason(event.target.value)}
                />
              </label>

              {cancelMessage ? <div className="toastError">{cancelMessage}</div> : null}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setCancelTarget(null)}>
                  رجوع
                </button>

                <button className="dangerButton" disabled={cancelling}>
                  {cancelling ? "جارٍ الإلغاء..." : "تأكيد الإلغاء"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {collection ? (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <h2>قبض من العميل</h2>
            </div>

            <form onSubmit={saveCollection}>
              <div className="formGrid">
                <label className="field">
                  <span>المبلغ</span>

                  <input
                    type="number"
                    min="0.01"
                    step="0.01"
                    value={paymentAmount}
                    onChange={(event) => setPaymentAmount(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={paymentDate}
                    onChange={(event) => setPaymentDate(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>الصندوق</span>

                  <select
                    value={paymentCashbox}
                    onChange={(event) => setPaymentCashbox(event.target.value)}
                  >
                    <option value="">اختر</option>

                    {cashboxes.map((cashbox) => (
                      <option key={cashbox.id} value={cashbox.id}>
                        {cashbox.name} - {cashbox.currency}
                      </option>
                    ))}
                  </select>
                </label>

                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={
                    cashboxes.find((cashbox) => cashbox.id === paymentCashbox)?.currency ?? ""
                  }
                  baseCurrency={currency}
                  date={paymentDate}
                  value={txRate}
                  onChange={setTxRate}
                />

                <label className="field">
                  <span>طريقة الدفع</span>

                  <select
                    value={paymentMethod}
                    onChange={(event) => setPaymentMethod(event.target.value as PaymentMethod)}
                  >
                    {Object.entries(paymentMethodLabels).map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              {quoteLoading ? (
                <p className="muted">جارٍ احتساب سعر الصرف...</p>
              ) : paymentQuoteError ? (
                <div className="toastError">{paymentQuoteError}</div>
              ) : paymentCashAmount ? (
                <p>
                  سيتم قبض {paymentCashAmount} {paymentCashCurrency}
                </p>
              ) : null}

              {paymentMessage ? <div className="toastError">{paymentMessage}</div> : null}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setCollection(null)}>
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={collecting || quoteLoading || Boolean(paymentQuoteError)}
                >
                  {collecting ? "جارٍ التسجيل..." : "تسجيل القبض"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
      {detailsOrder ? (
        <OrderDetails
          order={detailsOrder}
          companyId={companyId}
          currency={currency}
          canCancelInvoice={canCancelInvoice}
          canReversePayment={canReversePayment}
          onClose={() => setDetailsOrder(null)}
          onChanged={() => router.refresh()}
        />
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
