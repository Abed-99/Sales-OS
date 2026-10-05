"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { Icons } from "@/components/icons";
import { SearchPicker } from "@/components/search-picker";
import { UnitToggle } from "@/components/unit-toggle";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import {
  convertPrice,
  toBasePrice,
  toBaseQuantity,
  type UnitMode,
} from "@/lib/units";
import { productOption, searchProducts, searchSuppliers } from "@/lib/pickers";
import { createClient } from "@/lib/supabase/client";
import { NumberInput } from "@/components/number-input";
import { formatMoney as money, formatQty, todayDamascus as businessDateInput } from "@/lib/format";

export type PurchaseNeed = {
  sales_order_item_id: string;
  order_id: string;
  trader_name: string;
  product_id: string;
  product_name: string;
  sku: string | null;
  required_quantity: number;
  allocated_quantity: number;
  remaining_quantity: number;
  ordered_at: string;
};

export type SupplierOption = {
  id: string;
  name: string;
  active: boolean;
};

export type ProductOption = {
  id: string;
  name: string;
  sku: string | null;
  unit: string;
  active: boolean;
  pack_size?: number | null;
  pack_unit?: string | null;
};

export type SupplierPriceOption = {
  supplier_id: string;
  product_id: string;
  purchase_price: number;
  available: boolean;
};

export type CashboxOption = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
};

type InvoiceSupplier = {
  id: string;
  name: string;
};

export type PurchaseInvoiceRow = {
  id: string;
  invoice_number: string;
  supplier_invoice_number: string | null;
  status: string;
  payment_status: string;
  currency: string;
  invoice_date: string;
  due_date: string | null;
  total: number;
  paid_total: number;
  balance_due: number;
  cancellation_reason: string | null;
  created_at: string;
  suppliers: InvoiceSupplier | InvoiceSupplier[] | null;
};

type PaymentSupplier = {
  id: string;
  name: string;
};

type PaymentCashbox = {
  id: string;
  name: string;
  currency: string;
};

export type SupplierPaymentRow = {
  id: string;
  supplier_id: string;
  cashbox_id: string;
  payment_number: string;
  status: string;
  payment_date: string;
  amount: number;
  allocated_total: number;
  unallocated_total: number;
  payment_currency: string | null;
  exchange_rate_to_base: number | null;
  base_amount: number | null;
  payment_method: string;
  reference_number: string | null;
  notes: string | null;
  reversal_reason: string | null;
  created_at: string;
  suppliers: PaymentSupplier | PaymentSupplier[] | null;
  cashboxes: PaymentCashbox | PaymentCashbox[] | null;
};

type PurchaseStats = {
  needCount: number;
  remainingUnits: number;
  invoiceCount: number;
  outstandingTotal: number;
  supplierCreditTotal: number;
};

type InvoiceStatusFilter = "all" | "posted" | "cancelled";

type PaymentStatusFilter = "all" | "posted" | "reversed";

type PaymentMethod = "cash" | "bank" | "card" | "check" | "other";

type DraftLine = {
  key: string;
  productId: string;
  quantity: string;
  unitCost: string;
  discountAmount: string;
  taxAmount: string;
  notes: string;
  salesOrderItemId: string | null;
  maxQuantity: number | null;
  traderName: string | null;
  productName?: string | null;
  mode?: UnitMode;
  unit?: string | null;
  packSize?: number | null;
  packUnit?: string | null;
};

type InvoiceDetailLine = {
  id: string;
  quantity: number;
  unit_cost: number;
  discount_amount: number;
  tax_amount: number;
  line_total: number;
  notes: string | null;
  received: number | null;
  products:
    | { name: string; sku: string | null; unit: string }
    | { name: string; sku: string | null; unit: string }[]
    | null;
};

type Notice = {
  type: "success" | "error";
  text: string;
};

const paymentMethodLabels: Record<PaymentMethod, string> = {
  cash: "نقدي",
  bank: "تحويل بنكي",
  card: "بطاقة",
  check: "شيك",
  other: "أخرى",
};

function oneRelation<T>(value: T | T[] | null) {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function newKey() {
  return crypto.randomUUID();
}

function friendlyError(
  error: {
    code?: string;
    message?: string;
  } | null,
  action: "invoice" | "payment" | "cancel" | "reverse" | "quote",
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

  if (
    message.includes("archived supplier") ||
    message.includes("invalid supplier")
  ) {
    return "المورد غير صالح أو مؤرشف.";
  }

  if (
    message.includes("archived product") ||
    message.includes("invalid product")
  ) {
    return "أحد الأصناف غير صالح أو مؤرشف.";
  }

  if (message.includes("due date")) {
    return "تاريخ الاستحقاق لا يمكن أن يكون قبل تاريخ الفاتورة.";
  }

  if (message.includes("discount exceeds")) {
    return "الخصم لا يمكن أن يكون أكبر من قيمة البضاعة في السطر.";
  }

  if (message.includes("allocation exceeds")) {
    return "أحد المبالغ الموزعة أكبر من الرصيد المسموح.";
  }

  if (message.includes("reverse goods receipts")) {
    return "لا يمكن إلغاء الفاتورة قبل عكس استلام البضاعة المرتبط بها.";
  }

  if (message.includes("reverse allocated supplier payments")) {
    return "لا يمكن إلغاء الفاتورة قبل عكس دفعات المورد الموزعة عليها.";
  }

  if (message.includes("cancellation reason")) {
    return "سبب إلغاء الفاتورة مطلوب.";
  }

  if (message.includes("reversal reason")) {
    return "سبب عكس الدفعة مطلوب.";
  }

  if (
    message.includes("currency") ||
    message.includes("exchange") ||
    message.includes("rate")
  ) {
    return "تعذر احتساب سعر الصرف لهذه العملية.";
  }

  if (action === "invoice") {
    return "تعذر إنشاء فاتورة الشراء. راجع البيانات وحاول مرة ثانية.";
  }

  if (action === "payment") {
    return "تعذر تسجيل دفعة المورد. راجع البيانات وحاول مرة ثانية.";
  }

  if (action === "cancel") {
    return "تعذر إلغاء فاتورة الشراء.";
  }

  if (action === "reverse") {
    return "تعذر عكس دفعة المورد.";
  }

  return "تعذر احتساب المبلغ بعملة الصندوق.";
}

function emptyManualLine(): DraftLine {
  return {
    key: newKey(),
    productId: "",
    quantity: "1",
    unitCost: "",
    discountAmount: "0",
    taxAmount: "0",
    notes: "",
    salesOrderItemId: null,
    maxQuantity: null,
    traderName: null,
  };
}

export function PurchasesClient({
  companyId,
  currency,
  needs,
  suppliers,
  products,
  supplierPrices,
  initialInvoices,
  cashboxes,
  initialPayments,
  initialError,
  initialStats,
  invoiceTotalCount,
  invoicePage,
  paymentTotalCount,
  paymentPage,
  pageSize,
  invoiceSearchQuery,
  invoiceStatusFilter,
  paymentSearchQuery,
  paymentStatusFilter,
  canCreateInvoice,
  canCancelInvoice,
  canPaySupplier,
  canViewPayments,
  canReversePayment,
}: {
  companyId: string;
  currency: string;
  needs: PurchaseNeed[];
  suppliers: SupplierOption[];
  products: ProductOption[];
  supplierPrices: SupplierPriceOption[];
  initialInvoices: PurchaseInvoiceRow[];
  cashboxes: CashboxOption[];
  initialPayments: SupplierPaymentRow[];
  initialError: string | null;
  initialStats: PurchaseStats;
  invoiceTotalCount: number;
  invoicePage: number;
  paymentTotalCount: number;
  paymentPage: number;
  pageSize: number;
  invoiceSearchQuery: string;
  invoiceStatusFilter: InvoiceStatusFilter;
  paymentSearchQuery: string;
  paymentStatusFilter: PaymentStatusFilter;
  canCreateInvoice: boolean;
  canCancelInvoice: boolean;
  canPaySupplier: boolean;
  canViewPayments: boolean;
  canReversePayment: boolean;
}) {
  const [supabase] = useState(() => createClient());

  const supplierOptions = useMemo(
    () => suppliers.map((row) => ({ id: row.id, label: row.name })),
    [suppliers],
  );
  const productOptions = useMemo(
    () =>
      products.map((row) =>
        productOption({
          id: row.id,
          name: row.name,
          sku: row.sku ?? null,
          unit: row.unit ?? null,
          sale_price: null,
          pack_size: row.pack_size ?? null,
          pack_unit: row.pack_unit ?? null,
        }),
      ),
    [products],
  );
  const findSuppliers = useMemo(
    () => (term: string) => searchSuppliers(supabase, companyId, term),
    [supabase, companyId],
  );
  const findProducts = useMemo(
    () => (term: string) => searchProducts(supabase, companyId, term),
    [supabase, companyId],
  );

  const router = useRouter();

  const searchParams = useSearchParams();

  const [invoices, setInvoices] = useState(initialInvoices);

  const [payments, setPayments] = useState(initialPayments);

  const [notice, setNotice] = useState<Notice | null>(
    initialError
      ? {
          type: "error",
          text: initialError,
        }
      : null,
  );

  const [invoiceSearch, setInvoiceSearch] = useState(invoiceSearchQuery);

  const [invoiceFilter, setInvoiceFilter] =
    useState<InvoiceStatusFilter>(invoiceStatusFilter);

  const [paymentSearch, setPaymentSearch] = useState(paymentSearchQuery);

  const [paymentFilter, setPaymentFilter] =
    useState<PaymentStatusFilter>(paymentStatusFilter);

  useEffect(() => {
    setInvoices(initialInvoices);
  }, [initialInvoices]);

  useEffect(() => {
    setPayments(initialPayments);
  }, [initialPayments]);

  useEffect(() => {
    setInvoiceSearch(invoiceSearchQuery);

    setInvoiceFilter(invoiceStatusFilter);
  }, [invoiceSearchQuery, invoiceStatusFilter]);

  useEffect(() => {
    setPaymentSearch(paymentSearchQuery);

    setPaymentFilter(paymentStatusFilter);
  }, [paymentSearchQuery, paymentStatusFilter]);

  useEffect(() => {
    if (initialError) {
      setNotice({
        type: "error",
        text: initialError,
      });
    }
  }, [initialError]);

  // ==========================================================
  // INVOICE FORM
  // ==========================================================

  const [invoiceOpen, setInvoiceOpen] = useState(false);

  const [supplierId, setSupplierId] = useState("");

  const [supplierInvoiceNumber, setSupplierInvoiceNumber] = useState("");

  const [invoiceDate, setInvoiceDate] = useState(businessDateInput());

  const [dueDate, setDueDate] = useState("");

  const [invoiceNotes, setInvoiceNotes] = useState("");

  const [lines, setLines] = useState<DraftLine[]>([]);

  const [invoiceMessage, setInvoiceMessage] = useState("");

  const [savingInvoice, setSavingInvoice] = useState(false);

  // ==========================================================
  // PAYMENT FORM
  // ==========================================================

  const [paymentOpen, setPaymentOpen] = useState(false);

  const [paymentSupplierId, setPaymentSupplierId] = useState("");

  const [paymentCashboxId, setPaymentCashboxId] = useState("");

  const [paymentAmount, setPaymentAmount] = useState("");

  const [paymentDate, setPaymentDate] = useState(businessDateInput());
  // سعر الصرف لحظة الدفع (1 دولار = كم ليرة).
  const [txRate, setTxRate] = useState("");

  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("cash");

  const [paymentReference, setPaymentReference] = useState("");

  const [paymentNotes, setPaymentNotes] = useState("");

  const [paymentAllocations, setPaymentAllocations] = useState<
    Record<string, string>
  >({});

  const [paymentCashAmount, setPaymentCashAmount] = useState("");

  const [paymentCashCurrency, setPaymentCashCurrency] = useState(currency);

  const [paymentInvoiceCurrency, setPaymentInvoiceCurrency] =
    useState(currency);

  const [paymentQuoteError, setPaymentQuoteError] = useState("");

  const [quoteLoading, setQuoteLoading] = useState(false);

  const [paymentMessage, setPaymentMessage] = useState("");

  const [savingPayment, setSavingPayment] = useState(false);

  // ==========================================================
  // CANCEL / REVERSE MODALS
  // ==========================================================

  const [cancelTarget, setCancelTarget] = useState<PurchaseInvoiceRow | null>(
    null,
  );

  const [cancelReason, setCancelReason] = useState("");

  const [cancelMessage, setCancelMessage] = useState("");

  const [cancelling, setCancelling] = useState(false);

  const [reverseTarget, setReverseTarget] = useState<SupplierPaymentRow | null>(
    null,
  );

  const [reverseReason, setReverseReason] = useState("");

  const [reverseMessage, setReverseMessage] = useState("");

  const [reversing, setReversing] = useState(false);

  // ==========================================================
  // MAPS / CALCULATIONS
  // ==========================================================

  const priceMap = useMemo(() => {
    const map = new Map<string, number>();

    for (const row of supplierPrices) {
      if (!row.available) {
        continue;
      }

      map.set(
        `${row.supplier_id}:${row.product_id}`,
        Number(row.purchase_price),
      );
    }

    return map;
  }, [supplierPrices]);

  const selectedNeedIds = useMemo(
    () =>
      new Set(
        lines
          .map((line) => line.salesOrderItemId)
          .filter((value): value is string => Boolean(value)),
      ),
    [lines],
  );

  const invoiceTotals = useMemo(() => {
    return lines.reduce(
      (result, line) => {
        const quantity = Number(line.quantity || 0);

        const cost = Number(line.unitCost || 0);

        const discount = Number(line.discountAmount || 0);

        const tax = Number(line.taxAmount || 0);

        const subtotal = quantity * cost;

        return {
          subtotal: result.subtotal + subtotal,

          discount: result.discount + discount,

          tax: result.tax + tax,

          total: result.total + Math.max(subtotal - discount + tax, 0),
        };
      },
      {
        subtotal: 0,
        discount: 0,
        tax: 0,
        total: 0,
      },
    );
  }, [lines]);

  // كل فواتير المورد المفتوحة من القاعدة، مش بس اللي ظاهرين بالصفحة الحالية
  // (القائمة بتعرض آخر 50 فاتورة، فالفواتير القديمة ما كانت تطلع للدفع).
  const [paymentInvoices, setPaymentInvoices] = useState<PurchaseInvoiceRow[]>(
    [],
  );

  useEffect(() => {
    let cancelled = false;

    if (!paymentSupplierId) {
      setPaymentInvoices([]);
      return;
    }

    void supabase
      .from("purchase_invoices")
      .select(
        "id,invoice_number,supplier_invoice_number,status,payment_status,currency,invoice_date,due_date,total,paid_total,balance_due,cancellation_reason,created_at,suppliers(id,name)",
      )
      .eq("company_id", companyId)
      .eq("supplier_id", paymentSupplierId)
      .eq("status", "posted")
      .gt("balance_due", 0)
      .order("invoice_date")
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) {
          setPaymentMessage("تعذر تحميل فواتير المورد المفتوحة.");
          setPaymentInvoices([]);
          return;
        }
        setPaymentInvoices((data ?? []) as PurchaseInvoiceRow[]);
      });

    return () => {
      cancelled = true;
    };
  }, [paymentSupplierId, companyId, supabase]);

  const paymentAllocated = useMemo(() => {
    return Object.values(paymentAllocations).reduce(
      (sum, value) => sum + Number(value || 0),
      0,
    );
  }, [paymentAllocations]);

  const invoicePageCount = Math.max(1, Math.ceil(invoiceTotalCount / pageSize));

  const paymentPageCount = Math.max(1, Math.ceil(paymentTotalCount / pageSize));

  // ==========================================================
  // URL NAVIGATION
  // ==========================================================

  function navigateInvoices(
    nextSearch: string,
    nextFilter: InvoiceStatusFilter,
    nextPage = 1,
  ) {
    const params = new URLSearchParams(searchParams.toString());

    const clean = nextSearch.trim();

    if (clean) {
      params.set("iq", clean);
    } else {
      params.delete("iq");
    }

    if (nextFilter !== "all") {
      params.set("istatus", nextFilter);
    } else {
      params.delete("istatus");
    }

    if (nextPage > 1) {
      params.set("ipage", String(nextPage));
    } else {
      params.delete("ipage");
    }

    router.push(
      `/purchases${params.toString() ? `?${params.toString()}` : ""}`,
    );
  }

  function navigatePayments(
    nextSearch: string,
    nextFilter: PaymentStatusFilter,
    nextPage = 1,
  ) {
    const params = new URLSearchParams(searchParams.toString());

    const clean = nextSearch.trim();

    if (clean) {
      params.set("pq", clean);
    } else {
      params.delete("pq");
    }

    if (nextFilter !== "all") {
      params.set("pstatus", nextFilter);
    } else {
      params.delete("pstatus");
    }

    if (nextPage > 1) {
      params.set("ppage", String(nextPage));
    } else {
      params.delete("ppage");
    }

    router.push(
      `/purchases${params.toString() ? `?${params.toString()}` : ""}`,
    );
  }

  // ==========================================================
  // INVOICE HELPERS
  // ==========================================================

  function resetInvoiceForm() {
    setSupplierId("");
    setSupplierInvoiceNumber("");
    setInvoiceDate(businessDateInput());
    setDueDate("");
    setInvoiceNotes("");
    setLines([]);
    setInvoiceMessage("");
  }

  function startInvoice() {
    if (!canCreateInvoice) {
      return;
    }

    resetInvoiceForm();
    setInvoiceOpen(true);
  }

  function changeSupplier(value: string) {
    setSupplierId(value);

    setLines([]);
    setInvoiceMessage("");
  }

  function priceForProduct(productId: string) {
    if (!supplierId || !productId) {
      return null;
    }

    return priceMap.get(`${supplierId}:${productId}`) ?? null;
  }

  function addNeed(need: PurchaseNeed) {
    if (!supplierId) {
      setInvoiceMessage("اختر المورد أولاً.");
      return;
    }

    if (selectedNeedIds.has(need.sales_order_item_id)) {
      return;
    }

    const currentPrice = priceForProduct(need.product_id);

    setLines((current) => [
      ...current,
      {
        key: newKey(),
        productId: need.product_id,
        quantity: String(Number(need.remaining_quantity)),
        unitCost: currentPrice != null ? String(currentPrice) : "",
        discountAmount: "0",
        taxAmount: "0",
        notes: "",
        salesOrderItemId: need.sales_order_item_id,
        maxQuantity: Number(need.remaining_quantity),
        traderName: need.trader_name || null,
        productName: need.product_name,
      },
    ]);

    setInvoiceMessage("");
  }

  function addManualLine() {
    if (!supplierId) {
      setInvoiceMessage("اختر المورد أولاً.");
      return;
    }

    setLines((current) => [...current, emptyManualLine()]);
  }

  function updateLine(key: string, patch: Partial<DraftLine>) {
    setLines((current) =>
      current.map((line) =>
        line.key === key
          ? {
              ...line,
              ...patch,
            }
          : line,
      ),
    );
  }

  function chooseProduct(
    line: DraftLine,
    productId: string,
    productName?: string,
    picked?: {
      unit?: string | null;
      pack_size?: number | null;
      pack_unit?: string | null;
    },
  ) {
    const price = supplierId
      ? priceMap.get(`${supplierId}:${productId}`)
      : null;
    const product = products.find((row) => row.id === productId) ?? picked;

    updateLine(line.key, {
      productId,
      productName: productName ?? null,
      unitCost: price != null ? String(price) : "",
      mode: "base",
      unit: product?.unit ?? null,
      packSize: product?.pack_size ?? null,
      packUnit: product?.pack_unit ?? null,
    });
  }

  async function saveInvoice(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    setInvoiceMessage("");

    if (!canCreateInvoice) {
      setInvoiceMessage("ما عندك صلاحية إنشاء فاتورة شراء.");
      return;
    }

    if (!supplierId) {
      setInvoiceMessage("اختر المورد.");
      return;
    }

    if (!invoiceDate) {
      setInvoiceMessage("تاريخ الفاتورة مطلوب.");
      return;
    }

    if (dueDate && dueDate < invoiceDate) {
      setInvoiceMessage("تاريخ الاستحقاق لا يمكن أن يكون قبل تاريخ الفاتورة.");
      return;
    }

    if (!lines.length) {
      setInvoiceMessage("أضف بنداً واحداً على الأقل.");
      return;
    }

    for (const line of lines) {
      const quantity = Number(line.quantity);

      const cost = Number(line.unitCost);

      const discount = Number(line.discountAmount || 0);

      const tax = Number(line.taxAmount || 0);

      if (!line.productId) {
        setInvoiceMessage("يوجد بند بدون صنف.");
        return;
      }

      if (!Number.isFinite(quantity) || quantity <= 0) {
        setInvoiceMessage("راجع كميات الفاتورة.");
        return;
      }

      if (line.maxQuantity != null && quantity > line.maxQuantity) {
        setInvoiceMessage("إحدى الكميات أكبر من احتياج الشراء المتبقي.");
        return;
      }

      if (!Number.isFinite(cost) || cost < 0) {
        setInvoiceMessage("راجع أسعار الشراء.");
        return;
      }

      if (
        !Number.isFinite(discount) ||
        discount < 0 ||
        !Number.isFinite(tax) ||
        tax < 0
      ) {
        setInvoiceMessage("راجع الخصم والضريبة.");
        return;
      }

      if (discount > quantity * cost + 0.001) {
        setInvoiceMessage(
          "الخصم لا يمكن أن يكون أكبر من قيمة البضاعة في السطر.",
        );
        return;
      }
    }

    const payload = lines.map((line) => ({
      product_id: line.productId,

      // الكرتونة بتتحوّل لقطع (المخزون بالقطعة).
      quantity: toBaseQuantity(Number(line.quantity), line.mode, line.packSize),

      unit_cost: toBasePrice(Number(line.unitCost), line.mode, line.packSize),

      discount_amount: Number(line.discountAmount || 0),

      tax_amount: Number(line.taxAmount || 0),

      notes: line.notes.trim() || null,

      allocations: line.salesOrderItemId
        ? [
            {
              sales_order_item_id: line.salesOrderItemId,

              quantity: Number(line.quantity),
            },
          ]
        : [],
    }));

    setSavingInvoice(true);

    try {
      const { error } = await supabase.rpc("create_purchase_invoice", {
        target_company: companyId,

        target_supplier: supplierId,

        target_supplier_invoice_number: supplierInvoiceNumber.trim() || null,

        target_invoice_date: invoiceDate,

        target_due_date: dueDate || null,

        target_notes: invoiceNotes.trim() || null,

        items_payload: payload,
      });

      if (error) {
        setInvoiceMessage(friendlyError(error, "invoice"));
        return;
      }

      setInvoiceOpen(false);

      resetInvoiceForm();

      setNotice({
        type: "success",
        text: "تم إنشاء فاتورة الشراء بنجاح.",
      });

      router.refresh();
    } finally {
      setSavingInvoice(false);
    }
  }

  // ==========================================================
  // PAYMENT HELPERS
  // ==========================================================

  function resetPaymentForm() {
    setPaymentSupplierId("");

    const preferred =
      cashboxes.find((row) => row.currency === currency) ?? cashboxes[0];

    setPaymentCashboxId(preferred?.id ?? "");

    setPaymentAmount("");

    setPaymentDate(businessDateInput());

    setPaymentMethod("cash");

    setPaymentReference("");

    setPaymentNotes("");

    setPaymentAllocations({});

    setPaymentCashAmount("");

    setPaymentCashCurrency(preferred?.currency ?? currency);

    setPaymentInvoiceCurrency(currency);

    setPaymentQuoteError("");

    setPaymentMessage("");
  }

  function startPayment(invoice?: PurchaseInvoiceRow) {
    if (!canPaySupplier) {
      return;
    }

    resetPaymentForm();

    if (invoice) {
      const supplier = oneRelation(invoice.suppliers);

      const balance = Number(invoice.balance_due || 0);

      const matchingCashbox = cashboxes.find(
        (row) => row.currency === invoice.currency,
      );

      setPaymentSupplierId(supplier?.id ?? "");

      setPaymentAmount(balance > 0 ? balance.toFixed(2) : "");

      setPaymentAllocations(
        balance > 0
          ? {
              [invoice.id]: balance.toFixed(2),
            }
          : {},
      );

      if (matchingCashbox) {
        setPaymentCashboxId(matchingCashbox.id);
      }
    }

    setPaymentOpen(true);
  }

  function changePaymentSupplier(value: string) {
    setPaymentSupplierId(value);

    setPaymentAllocations({});

    setPaymentMessage("");
  }

  function setAllocation(invoiceId: string, value: string) {
    setPaymentAllocations((current) => ({
      ...current,
      [invoiceId]: value,
    }));
  }

  function allocateInvoice(invoice: PurchaseInvoiceRow) {
    const balance = Number(invoice.balance_due || 0);

    const other = Object.entries(paymentAllocations).reduce(
      (sum, [id, value]) =>
        id === invoice.id ? sum : sum + Number(value || 0),
      0,
    );

    const available = Math.max(Number(paymentAmount || 0) - other, 0);

    setAllocation(
      invoice.id,
      Math.min(available, balance) > 0
        ? Math.min(available, balance).toFixed(2)
        : "",
    );
  }

  useEffect(() => {
    let cancelled = false;

    async function quote() {
      if (!paymentOpen) {
        return;
      }

      const cashbox = cashboxes.find((row) => row.id === paymentCashboxId);

      const amount = Number(paymentAmount || 0);

      if (!cashbox || !paymentDate || !Number.isFinite(amount) || amount <= 0) {
        setPaymentCashAmount("");

        setPaymentQuoteError("");

        setQuoteLoading(false);

        return;
      }

      const invoiceCurrency = paymentInvoices[0]?.currency ?? currency;

      if (
        paymentInvoices.some((invoice) => invoice.currency !== invoiceCurrency)
      ) {
        setPaymentQuoteError(
          "لا يمكن توزيع دفعة واحدة على فواتير بعملات مختلفة.",
        );

        setPaymentCashAmount("");

        return;
      }

      setPaymentCashCurrency(cashbox.currency);

      setPaymentInvoiceCurrency(invoiceCurrency);

      if (cashbox.currency === invoiceCurrency) {
        setPaymentCashAmount(amount.toFixed(2));

        setPaymentQuoteError("");

        setQuoteLoading(false);

        return;
      }

      if (invoiceCurrency === currency && Number(txRate) > 0) {
        setPaymentCashAmount((amount * Number(txRate)).toFixed(2));
        setPaymentQuoteError("");
        setQuoteLoading(false);
        return;
      }

      setQuoteLoading(true);

      setPaymentCashAmount("");

      const { data, error } = await supabase.rpc("payment_currency_quote", {
        target_company: companyId,

        target_invoice_currency: invoiceCurrency,

        target_payment_currency: cashbox.currency,

        target_invoice_amount: amount,

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

      const result = Array.isArray(data) ? data[0] : data;

      const cashAmount = Number(result?.payment_amount ?? 0);

      if (!Number.isFinite(cashAmount) || cashAmount <= 0) {
        setPaymentQuoteError("تعذر احتساب مبلغ الصندوق.");
        return;
      }

      setPaymentCashAmount(cashAmount.toFixed(2));

      setPaymentQuoteError("");
    }

    void quote();

    return () => {
      cancelled = true;
    };
  }, [
    txRate,
    paymentOpen,
    paymentCashboxId,
    paymentDate,
    paymentAmount,
    paymentInvoices,
    cashboxes,
    companyId,
    currency,
    supabase,
  ]);

  async function savePayment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    setPaymentMessage("");

    if (!canPaySupplier) {
      setPaymentMessage("ما عندك صلاحية تسجيل دفعة مورد.");
      return;
    }

    if (!paymentSupplierId) {
      setPaymentMessage("اختر المورد.");
      return;
    }

    const amount = Number(paymentAmount);

    if (!Number.isFinite(amount) || amount <= 0) {
      setPaymentMessage("اكتب مبلغ دفعة صحيح.");
      return;
    }

    const cashbox = cashboxes.find((row) => row.id === paymentCashboxId);

    if (!cashbox) {
      setPaymentMessage("اختر صندوقاً مالياً صالحاً.");
      return;
    }

    if (paymentAllocated > amount + 0.01) {
      setPaymentMessage("مجموع التوزيع أكبر من مبلغ الدفعة.");
      return;
    }

    const invoiceCurrency = paymentInvoices[0]?.currency ?? currency;

    if (
      paymentInvoices.some((invoice) => invoice.currency !== invoiceCurrency)
    ) {
      setPaymentMessage("لا يمكن دفع فواتير بعملات مختلفة في نفس العملية.");
      return;
    }

    const allocations: Array<{
      purchase_invoice_id: string;
      amount: number;
    }> = [];

    for (const invoice of paymentInvoices) {
      const value = Number(paymentAllocations[invoice.id] || 0);

      if (!Number.isFinite(value) || value < 0) {
        setPaymentMessage("راجع توزيع الدفعة.");
        return;
      }

      if (value <= 0) {
        continue;
      }

      if (value > Number(invoice.balance_due) + 0.01) {
        setPaymentMessage(
          `المبلغ الموزع على ${invoice.invoice_number} أكبر من رصيد الفاتورة.`,
        );
        return;
      }

      allocations.push({
        purchase_invoice_id: invoice.id,
        amount: Number(value.toFixed(2)),
      });
    }

    // إذا ما وزّع المستخدم شي: الدفعة بتنزل من أقدم الفواتير المفتوحة،
    // والزايد بس بيضل دفعة مقدمة. هيك دين المورد بينزل متل ما بيتوقع.
    if (!allocations.length) {
      let left = amount;
      for (const invoice of paymentInvoices) {
        const take = Math.min(left, Number(invoice.balance_due || 0));
        if (take <= 0) continue;
        allocations.push({
          purchase_invoice_id: invoice.id,
          amount: Number(take.toFixed(2)),
        });
        left = Number((left - take).toFixed(2));
        if (left <= 0) break;
      }
    }

    setSavingPayment(true);

    try {
      let cashAmount = amount;

      if (cashbox.currency !== invoiceCurrency) {
        const rateError = await applyTransactionRate(
          supabase,
          companyId,
          cashbox.currency,
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

          target_payment_currency: cashbox.currency,

          target_invoice_amount: amount,

          target_payment_date: paymentDate,
        });

        if (error) {
          setPaymentMessage(friendlyError(error, "quote"));
          return;
        }

        const result = Array.isArray(data) ? data[0] : data;

        cashAmount = Number(result?.payment_amount ?? 0);

        if (!Number.isFinite(cashAmount) || cashAmount <= 0) {
          setPaymentMessage("تعذر تثبيت مبلغ الدفعة بعملة الصندوق.");
          return;
        }
      }

      const { error } = await supabase.rpc("record_supplier_payment", {
        target_company: companyId,

        target_supplier: paymentSupplierId,

        target_cashbox: paymentCashboxId,

        target_amount: Number(cashAmount.toFixed(2)),

        target_payment_date: paymentDate,

        target_method: paymentMethod,

        target_reference: paymentReference.trim() || null,

        target_notes: paymentNotes.trim() || null,

        allocations_payload: allocations,
      });

      if (error) {
        setPaymentMessage(friendlyError(error, "payment"));
        return;
      }

      setPaymentOpen(false);

      resetPaymentForm();

      setNotice({
        type: "success",
        text: "تم تسجيل دفعة المورد بنجاح.",
      });

      router.refresh();
    } finally {
      setSavingPayment(false);
    }
  }

  // ==========================================================
  // INVOICE DETAILS
  // ==========================================================

  const [detailInvoice, setDetailInvoice] = useState<PurchaseInvoiceRow | null>(
    null,
  );
  const [detailLines, setDetailLines] = useState<InvoiceDetailLine[]>([]);
  const [detailMessage, setDetailMessage] = useState("");

  async function openDetails(invoice: PurchaseInvoiceRow) {
    setDetailInvoice(invoice);
    setDetailLines([]);
    setDetailMessage("عم نحمّل البنود...");

    const { data, error } = await supabase
      .from("purchase_invoice_items")
      .select(
        "id,quantity,unit_cost,discount_amount,tax_amount,line_total,notes,products(name,sku,unit)",
      )
      .eq("company_id", companyId)
      .eq("invoice_id", invoice.id)
      .order("created_at");

    if (error) {
      setDetailMessage("تعذر تحميل بنود الفاتورة.");
      return;
    }

    const rows = (data ?? []) as Omit<InvoiceDetailLine, "received">[];

    // الكمية المستلمة بالمستودع (إذا المستخدم بيقدر يشوف الاستلامات).
    const received = new Map<string, number>();
    let canSeeReceipts = true;

    if (rows.length) {
      const result = await supabase
        .from("goods_receipt_items")
        .select(
          "purchase_invoice_item_id,quantity,goods_receipts!inner(status)",
        )
        .in(
          "purchase_invoice_item_id",
          rows.map((row) => row.id),
        )
        .eq("goods_receipts.status", "posted");

      if (result.error) {
        canSeeReceipts = false;
      } else {
        for (const row of result.data ?? []) {
          const key = String(row.purchase_invoice_item_id);
          received.set(key, (received.get(key) ?? 0) + Number(row.quantity));
        }
      }
    }

    setDetailLines(
      rows.map((row) => ({
        ...row,
        received: canSeeReceipts ? (received.get(row.id) ?? 0) : null,
      })),
    );
    setDetailMessage("");
  }

  // ==========================================================
  // CANCEL INVOICE
  // ==========================================================

  function openCancel(invoice: PurchaseInvoiceRow) {
    if (!canCancelInvoice) {
      return;
    }

    setCancelTarget(invoice);

    setCancelReason("");

    setCancelMessage("");
  }

  async function saveCancel(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!cancelTarget || !canCancelInvoice) {
      return;
    }

    const reason = cancelReason.trim();

    if (!reason) {
      setCancelMessage("اكتب سبب إلغاء الفاتورة.");
      return;
    }

    setCancelling(true);

    try {
      const { error } = await supabase.rpc("cancel_purchase_invoice", {
        target_company: companyId,

        target_invoice: cancelTarget.id,

        target_reason: reason,
      });

      if (error) {
        setCancelMessage(friendlyError(error, "cancel"));
        return;
      }

      setInvoices((current) =>
        current.map((row) =>
          row.id === cancelTarget.id
            ? {
                ...row,
                status: "cancelled",
                cancellation_reason: reason,
              }
            : row,
        ),
      );

      setCancelTarget(null);

      setNotice({
        type: "success",
        text: "تم إلغاء فاتورة الشراء.",
      });

      router.refresh();
    } finally {
      setCancelling(false);
    }
  }

  // ==========================================================
  // REVERSE PAYMENT
  // ==========================================================

  function openReverse(payment: SupplierPaymentRow) {
    if (!canReversePayment) {
      return;
    }

    setReverseTarget(payment);

    setReverseReason("");

    setReverseMessage("");
  }

  async function saveReverse(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!reverseTarget || !canReversePayment) {
      return;
    }

    const reason = reverseReason.trim();

    if (!reason) {
      setReverseMessage("اكتب سبب عكس الدفعة.");
      return;
    }

    setReversing(true);

    try {
      const { error } = await supabase.rpc("reverse_supplier_payment", {
        target_company: companyId,

        target_payment: reverseTarget.id,

        target_reason: reason,
      });

      if (error) {
        setReverseMessage(friendlyError(error, "reverse"));
        return;
      }

      setPayments((current) =>
        current.map((row) =>
          row.id === reverseTarget.id
            ? {
                ...row,
                status: "reversed",
                reversal_reason: reason,
              }
            : row,
        ),
      );

      setReverseTarget(null);

      setNotice({
        type: "success",
        text: "تم عكس دفعة المورد وإرجاع أثرها المالي.",
      });

      router.refresh();
    } finally {
      setReversing(false);
    }
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">دورة الشراء</span>

          <h2>المشتريات والموردون</h2>

          <p className="muted">
            احتياجات الشراء، فواتير الموردين، الدفعات والرصيد المستحق.
          </p>
        </div>

        <div className="rowActions">
          {canPaySupplier ? (
            <button
              type="button"
              className="softButton"
              onClick={() => startPayment()}
            >
              <Icons.money size={15} />
              دفع لمورد
            </button>
          ) : null}

          {canCreateInvoice ? (
            <button
              type="button"
              className="primaryButton"
              onClick={startInvoice}
            >
              <Icons.plus size={15} />
              فاتورة شراء جديدة
            </button>
          ) : null}
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
        <Mini title="بنود مطلوبة" value={formatQty(initialStats.needCount)} />

        <Mini
          title="كميات متبقية"
          value={formatQty(Number(initialStats.remainingUnits.toFixed(3)))}
        />

        <Mini
          title="مستحق للموردين"
          value={money(initialStats.outstandingTotal, currency)}
        />

        <Mini
          title="دفعات مقدمة"
          value={money(initialStats.supplierCreditTotal, currency)}
        />
      </section>

      <section
        className="panel panelPad"
        style={{
          marginTop: 14,
        }}
      >
        <div className="panelHeader">
          <div>
            <h2>احتياجات الشراء المفتوحة</h2>

            <p>المطلوب والمتبقي من طلبيات العملاء.</p>
          </div>
        </div>

        {!needs.length ? (
          <div className="empty">
            <Icons.check size={30} />

            <h3>لا توجد احتياجات شراء</h3>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الصنف</th>
                  <th>العميل</th>
                  <th>المطلوب</th>
                  <th>مخصص للشراء</th>
                  <th>المتبقي</th>
                </tr>
              </thead>

              <tbody>
                {needs.map((need) => (
                  <tr key={need.sales_order_item_id}>
                    <td>
                      <strong>{need.product_name}</strong>

                      <div className="muted">{need.sku || "—"}</div>
                    </td>

                    <td>{need.trader_name}</td>

                    <td>{formatQty(need.required_quantity)}</td>

                    <td>{formatQty(need.allocated_quantity)}</td>

                    <td>
                      <strong>{formatQty(need.remaining_quantity)}</strong>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        <div className="panelPad">
          <div className="panelHeader">
            <div>
              <h2>فواتير الشراء</h2>

              <p>إجمالي الفواتير المثبتة: {initialStats.invoiceCount}</p>
            </div>
          </div>

          <form
            className="filters"
            onSubmit={(event) => {
              event.preventDefault();

              navigateInvoices(invoiceSearch, invoiceFilter, 1);
            }}
          >
            <div className="searchBox">
              <Icons.search size={16} />

              <input
                value={invoiceSearch}
                onChange={(event) => setInvoiceSearch(event.target.value)}
                placeholder="رقم الفاتورة، المورد، الصنف أو المبلغ..."
                aria-label="بحث في فواتير الشراء"
              />

              <button className="softButton" type="submit">
                بحث
              </button>
            </div>

            <select
              value={invoiceFilter}
              aria-label="حالة فاتورة الشراء"
              onChange={(event) => {
                const value = event.target.value as InvoiceStatusFilter;

                setInvoiceFilter(value);

                navigateInvoices(invoiceSearch, value, 1);
              }}
            >
              <option value="all">كل الحالات</option>

              <option value="posted">مثبتة</option>

              <option value="cancelled">ملغاة</option>
            </select>
          </form>
        </div>

        {!invoices.length ? (
          <div className="empty">
            <Icons.store size={28} />
            <h3>لا توجد فواتير شراء</h3>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الفاتورة</th>
                  <th>المورد</th>
                  <th>رقم المورد</th>
                  <th>التاريخ</th>
                  <th>الإجمالي</th>
                  <th>المدفوع</th>
                  <th>المتبقي</th>
                  <th>الحالة</th>
                  <th>إجراء</th>
                </tr>
              </thead>

              <tbody>
                {invoices.map((invoice) => {
                  const supplier = oneRelation(invoice.suppliers);

                  return (
                    <tr key={invoice.id}>
                      <td>
                        <button
                          type="button"
                          className="linkButton"
                          onClick={() => void openDetails(invoice)}
                          title="تفاصيل الفاتورة"
                        >
                          <strong>{invoice.invoice_number}</strong>
                        </button>
                        <div>
                          <Link
                            className="muted"
                            href={`/print/purchase/${invoice.id}`}
                          >
                            طباعة
                          </Link>
                        </div>
                      </td>

                      <td>{supplier?.name || "—"}</td>

                      <td>{invoice.supplier_invoice_number || "—"}</td>

                      <td>{invoice.invoice_date}</td>

                      <td>{money(invoice.total, invoice.currency)}</td>

                      <td>{money(invoice.paid_total, invoice.currency)}</td>

                      <td>
                        <strong>
                          {money(invoice.balance_due, invoice.currency)}
                        </strong>
                      </td>

                      <td>
                        {invoice.status === "cancelled" ? (
                          <>
                            <span className="chip gray">ملغاة</span>

                            {invoice.cancellation_reason ? (
                              <div className="muted">
                                {invoice.cancellation_reason}
                              </div>
                            ) : null}
                          </>
                        ) : (
                          <span
                            className={`chip ${
                              invoice.payment_status === "paid"
                                ? "green"
                                : invoice.payment_status === "partial"
                                  ? "orange"
                                  : "gray"
                            }`}
                          >
                            {invoice.payment_status === "paid"
                              ? "مدفوعة"
                              : invoice.payment_status === "partial"
                                ? "جزئية"
                                : "غير مدفوعة"}
                          </span>
                        )}
                      </td>

                      <td>
                        <div className="rowActions">
                          {canPaySupplier &&
                          invoice.status === "posted" &&
                          Number(invoice.balance_due) > 0 ? (
                            <button
                              type="button"
                              className="primaryButton"
                              onClick={() => startPayment(invoice)}
                            >
                              دفع
                            </button>
                          ) : null}

                          {canCancelInvoice && invoice.status === "posted" ? (
                            <button
                              type="button"
                              className="dangerButton"
                              onClick={() => openCancel(invoice)}
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

        {invoicePageCount > 1 ? (
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
              disabled={invoicePage <= 1}
              onClick={() =>
                navigateInvoices(
                  invoiceSearchQuery,
                  invoiceStatusFilter,
                  invoicePage - 1,
                )
              }
            >
              السابق
            </button>

            <span className="muted">
              صفحة {invoicePage} من {invoicePageCount}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={invoicePage >= invoicePageCount}
              onClick={() =>
                navigateInvoices(
                  invoiceSearchQuery,
                  invoiceStatusFilter,
                  invoicePage + 1,
                )
              }
            >
              التالي
            </button>
          </div>
        ) : null}
      </section>

      {canViewPayments ? (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelPad">
            <div className="panelHeader">
              <div>
                <h2>دفعات الموردين</h2>

                <p>الدفعات المثبتة والمعكوسة.</p>
              </div>
            </div>

            <form
              className="filters"
              onSubmit={(event) => {
                event.preventDefault();

                navigatePayments(paymentSearch, paymentFilter, 1);
              }}
            >
              <div className="searchBox">
                <Icons.search size={16} />

                <input
                  value={paymentSearch}
                  onChange={(event) => setPaymentSearch(event.target.value)}
                  placeholder="رقم الدفعة، المورد، المرجع أو المبلغ..."
                  aria-label="بحث في دفعات الموردين"
                />

                <button className="softButton" type="submit">
                  بحث
                </button>
              </div>

              <select
                value={paymentFilter}
                aria-label="حالة دفعة المورد"
                onChange={(event) => {
                  const value = event.target.value as PaymentStatusFilter;

                  setPaymentFilter(value);

                  navigatePayments(paymentSearch, value, 1);
                }}
              >
                <option value="all">كل الحالات</option>

                <option value="posted">مثبتة</option>

                <option value="reversed">معكوسة</option>
              </select>
            </form>
          </div>

          {!payments.length ? (
            <div className="empty">
              <Icons.money size={28} />

              <h3>لا توجد دفعات موردين</h3>
            </div>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الدفعة</th>
                    <th>المورد</th>
                    <th>المبلغ</th>
                    <th>الموزع</th>
                    <th>المقدم</th>
                    <th>الصندوق</th>
                    <th>التاريخ</th>
                    <th>الحالة</th>
                    <th>إجراء</th>
                  </tr>
                </thead>

                <tbody>
                  {payments.map((payment) => {
                    const supplier = oneRelation(payment.suppliers);

                    const cashbox = oneRelation(payment.cashboxes);

                    const paymentCurrency =
                      payment.payment_currency || cashbox?.currency || currency;

                    return (
                      <tr key={payment.id}>
                        <td>
                          <strong>{payment.payment_number}</strong>

                          <div className="muted">
                            {payment.reference_number || ""}
                          </div>
                          <Link
                            className="muted"
                            href={`/print/receipt/${payment.id}?kind=supplier`}
                          >
                            سند دفع
                          </Link>
                        </td>

                        <td>{supplier?.name || "—"}</td>

                        <td>
                          {money(payment.amount, paymentCurrency)}

                          {payment.base_amount != null &&
                          paymentCurrency !== currency ? (
                            <div className="muted">
                              ≈ {money(payment.base_amount, currency)}
                            </div>
                          ) : null}
                        </td>

                        <td>
                          {money(payment.allocated_total, paymentCurrency)}
                        </td>

                        <td>
                          {money(payment.unallocated_total, paymentCurrency)}
                        </td>

                        <td>{cashbox?.name || "—"}</td>

                        <td>{payment.payment_date}</td>

                        <td>
                          <span
                            className={`chip ${payment.status === "posted" ? "green" : "gray"}`}
                          >
                            {payment.status === "posted" ? "مثبتة" : "معكوسة"}
                          </span>

                          {payment.status === "reversed" &&
                          payment.reversal_reason ? (
                            <div className="muted">
                              {payment.reversal_reason}
                            </div>
                          ) : null}
                        </td>

                        <td>
                          {canReversePayment && payment.status === "posted" ? (
                            <button
                              type="button"
                              className="dangerButton"
                              onClick={() => openReverse(payment)}
                            >
                              عكس
                            </button>
                          ) : null}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {paymentPageCount > 1 ? (
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
                disabled={paymentPage <= 1}
                onClick={() =>
                  navigatePayments(
                    paymentSearchQuery,
                    paymentStatusFilter,
                    paymentPage - 1,
                  )
                }
              >
                السابق
              </button>

              <span className="muted">
                صفحة {paymentPage} من {paymentPageCount}
              </span>

              <button
                type="button"
                className="softButton"
                disabled={paymentPage >= paymentPageCount}
                onClick={() =>
                  navigatePayments(
                    paymentSearchQuery,
                    paymentStatusFilter,
                    paymentPage + 1,
                  )
                }
              >
                التالي
              </button>
            </div>
          ) : null}
        </section>
      ) : null}

      {invoiceOpen ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              maxWidth: 1050,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <h2>فاتورة شراء جديدة</h2>

              <button
                type="button"
                className="closeButton"
                disabled={savingInvoice}
                onClick={() => setInvoiceOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveInvoice}>
              <div className="formGrid">
                <label className="field">
                  <span>المورد *</span>

                  <SearchPicker
                    value={supplierId}
                    placeholder="اكتب اسم المورد..."
                    options={supplierOptions}
                    onSearch={findSuppliers}
                    onChange={(id) => changeSupplier(id)}
                  />
                </label>

                <label className="field">
                  <span>رقم فاتورة المورد</span>

                  <input
                    value={supplierInvoiceNumber}
                    onChange={(event) =>
                      setSupplierInvoiceNumber(event.target.value)
                    }
                  />
                </label>

                <label className="field">
                  <span>تاريخ الفاتورة *</span>

                  <input
                    type="date"
                    value={invoiceDate}
                    onChange={(event) => setInvoiceDate(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>تاريخ الاستحقاق</span>

                  <input
                    type="date"
                    min={invoiceDate}
                    value={dueDate}
                    onChange={(event) => setDueDate(event.target.value)}
                  />
                </label>
              </div>

              {supplierId && needs.length ? (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 15,
                  }}
                >
                  <h3>احتياجات الشراء</h3>

                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th>الصنف</th>
                          <th>العميل</th>
                          <th>المتبقي</th>
                          <th>إضافة</th>
                        </tr>
                      </thead>

                      <tbody>
                        {needs.map((need) => (
                          <tr key={need.sales_order_item_id}>
                            <td>{need.product_name}</td>

                            <td>{need.trader_name}</td>

                            <td>{formatQty(need.remaining_quantity)}</td>

                            <td>
                              <button
                                type="button"
                                className="softButton"
                                disabled={selectedNeedIds.has(
                                  need.sales_order_item_id,
                                )}
                                onClick={() => addNeed(need)}
                              >
                                {selectedNeedIds.has(need.sales_order_item_id)
                                  ? "مضاف"
                                  : "إضافة"}
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              ) : null}

              <div
                className="panel panelPad"
                style={{
                  marginTop: 15,
                }}
              >
                <div className="panelHeader">
                  <h3>بنود الفاتورة</h3>

                  <button
                    type="button"
                    className="softButton"
                    onClick={addManualLine}
                  >
                    <Icons.plus size={14} />
                    بند يدوي
                  </button>
                </div>

                {!lines.length ? (
                  <p className="muted">لا توجد بنود مضافة.</p>
                ) : (
                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th>الصنف</th>
                          <th>الكمية</th>
                          <th>الكلفة</th>
                          <th>الخصم</th>
                          <th>الضريبة</th>
                          <th>الإجمالي</th>
                          <th />
                        </tr>
                      </thead>

                      <tbody>
                        {lines.map((line) => {
                          const quantity = Number(line.quantity || 0);

                          const cost = Number(line.unitCost || 0);

                          const discount = Number(line.discountAmount || 0);

                          const tax = Number(line.taxAmount || 0);

                          return (
                            <tr key={line.key}>
                              <td>
                                {line.salesOrderItemId ? (
                                  <>
                                    <strong>
                                      {products.find(
                                        (product) =>
                                          product.id === line.productId,
                                      )?.name ?? line.productName}
                                    </strong>

                                    <div className="muted">
                                      {line.traderName
                                        ? `للعميل: ${line.traderName}`
                                        : ""}
                                    </div>
                                  </>
                                ) : (
                                  <SearchPicker
                                    value={line.productId}
                                    placeholder="اسم الصنف أو كودو..."
                                    options={productOptions}
                                    onSearch={findProducts}
                                    onChange={(id, option) =>
                                      chooseProduct(
                                        line,
                                        id,
                                        option?.label,
                                        option?.data as
                                          | {
                                              unit?: string | null;
                                              pack_size?: number | null;
                                              pack_unit?: string | null;
                                            }
                                          | undefined,
                                      )
                                    }
                                  />
                                )}
                              </td>

                              <td>
                                <NumberInput
                                  min="0.001"
                                  step="0.001"
                                  value={line.quantity}
                                  onChange={(event) =>
                                    updateLine(line.key, {
                                      quantity: event.target.value,
                                    })
                                  }
                                />

                                {line.salesOrderItemId ? null : (
                                  <UnitToggle
                                    mode={line.mode}
                                    unit={line.unit}
                                    packUnit={line.packUnit}
                                    packSize={line.packSize}
                                    quantity={line.quantity}
                                    onChange={(mode) =>
                                      updateLine(line.key, {
                                        mode,
                                        unitCost: convertPrice(
                                          line.unitCost,
                                          line.mode,
                                          mode,
                                          line.packSize,
                                        ),
                                      })
                                    }
                                  />
                                )}
                              </td>

                              <td>
                                <NumberInput
                                  min="0"
                                  step="0.01"
                                  value={line.unitCost}
                                  onChange={(event) =>
                                    updateLine(line.key, {
                                      unitCost: event.target.value,
                                    })
                                  }
                                />
                              </td>

                              <td>
                                <NumberInput
                                  min="0"
                                  step="0.01"
                                  value={line.discountAmount}
                                  onChange={(event) =>
                                    updateLine(line.key, {
                                      discountAmount: event.target.value,
                                    })
                                  }
                                />
                              </td>

                              <td>
                                <NumberInput
                                  min="0"
                                  step="0.01"
                                  value={line.taxAmount}
                                  onChange={(event) =>
                                    updateLine(line.key, {
                                      taxAmount: event.target.value,
                                    })
                                  }
                                />
                              </td>

                              <td>
                                {money(
                                  Math.max(quantity * cost - discount + tax, 0),
                                  currency,
                                )}
                              </td>

                              <td>
                                <button
                                  type="button"
                                  className="dangerButton"
                                  onClick={() =>
                                    setLines((current) =>
                                      current.filter(
                                        (row) => row.key !== line.key,
                                      ),
                                    )
                                  }
                                >
                                  ×
                                </button>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}

                <div
                  style={{
                    marginTop: 14,
                  }}
                >
                  <strong>
                    الإجمالي: {money(invoiceTotals.total, currency)}
                  </strong>
                </div>
              </div>

              <label
                className="field"
                style={{
                  marginTop: 15,
                }}
              >
                <span>ملاحظات</span>

                <textarea
                  value={invoiceNotes}
                  onChange={(event) => setInvoiceNotes(event.target.value)}
                />
              </label>

              {invoiceMessage ? (
                <div className="toastError" role="alert">
                  {invoiceMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={savingInvoice}
                  onClick={() => setInvoiceOpen(false)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={savingInvoice}>
                  {savingInvoice ? "جارٍ الحفظ..." : "حفظ الفاتورة"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {paymentOpen ? (
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
              <h2>دفع لمورد</h2>

              <button
                type="button"
                className="closeButton"
                disabled={savingPayment}
                onClick={() => setPaymentOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={savePayment}>
              <div className="formGrid">
                <label className="field">
                  <span>المورد *</span>

                  <SearchPicker
                    value={paymentSupplierId}
                    placeholder="اكتب اسم المورد..."
                    options={supplierOptions}
                    onSearch={findSuppliers}
                    onChange={(id) => changePaymentSupplier(id)}
                  />
                </label>

                <label className="field">
                  <span>المبلغ ({paymentInvoiceCurrency})</span>

                  <NumberInput
                    min="0.01"
                    step="0.01"
                    value={paymentAmount}
                    onChange={(event) => setPaymentAmount(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>الصندوق *</span>

                  <select
                    value={paymentCashboxId}
                    onChange={(event) =>
                      setPaymentCashboxId(event.target.value)
                    }
                  >
                    <option value="">اختر الصندوق</option>

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
                    cashboxes.find((cashbox) => cashbox.id === paymentCashboxId)
                      ?.currency ?? ""
                  }
                  baseCurrency={currency}
                  date={paymentDate}
                  value={txRate}
                  onChange={setTxRate}
                />

                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={paymentDate}
                    onChange={(event) => setPaymentDate(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>طريقة الدفع</span>

                  <select
                    value={paymentMethod}
                    onChange={(event) =>
                      setPaymentMethod(event.target.value as PaymentMethod)
                    }
                  >
                    {Object.entries(paymentMethodLabels).map(
                      ([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ),
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>المرجع</span>

                  <input
                    value={paymentReference}
                    onChange={(event) =>
                      setPaymentReference(event.target.value)
                    }
                  />
                </label>
              </div>

              {quoteLoading ? (
                <p className="muted">جارٍ احتساب سعر الصرف...</p>
              ) : paymentQuoteError ? (
                <div className="toastError">{paymentQuoteError}</div>
              ) : paymentCashAmount ? (
                <p>
                  سيخرج من الصندوق:{" "}
                  <strong>
                    {paymentCashAmount} {paymentCashCurrency}
                  </strong>
                </p>
              ) : null}

              {paymentInvoices.length ? (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 15,
                  }}
                >
                  <h3>توزيع الدفعة</h3>

                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th>الفاتورة</th>
                          <th>الرصيد</th>
                          <th>التوزيع</th>
                          <th />
                        </tr>
                      </thead>

                      <tbody>
                        {paymentInvoices.map((invoice) => (
                          <tr key={invoice.id}>
                            <td>{invoice.invoice_number}</td>

                            <td>
                              {money(invoice.balance_due, invoice.currency)}
                            </td>

                            <td>
                              <NumberInput
                                min="0"
                                step="0.01"
                                value={paymentAllocations[invoice.id] || ""}
                                onChange={(event) =>
                                  setAllocation(invoice.id, event.target.value)
                                }
                              />
                            </td>

                            <td>
                              <button
                                type="button"
                                className="softButton"
                                onClick={() => allocateInvoice(invoice)}
                              >
                                توزيع
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  <p className="muted">
                    موزع: {money(paymentAllocated, paymentInvoiceCurrency)}
                  </p>
                  {!paymentAllocated ? (
                    <p className="muted">
                      إذا ما وزّعت، الدفعة بتنزل لحالها من أقدم فاتورة، والزايد
                      بيضل دفعة مقدمة.
                    </p>
                  ) : null}
                </div>
              ) : null}

              <label
                className="field"
                style={{
                  marginTop: 15,
                }}
              >
                <span>ملاحظات</span>

                <textarea
                  value={paymentNotes}
                  onChange={(event) => setPaymentNotes(event.target.value)}
                />
              </label>

              {paymentMessage ? (
                <div className="toastError" role="alert">
                  {paymentMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={savingPayment}
                  onClick={() => setPaymentOpen(false)}
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    savingPayment || quoteLoading || Boolean(paymentQuoteError)
                  }
                >
                  {savingPayment ? "جارٍ التسجيل..." : "تسجيل الدفعة"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {detailInvoice ? (
        <div
          className="modalOverlay"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setDetailInvoice(null);
          }}
        >
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="purchase-detail-title"
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  {oneRelation(detailInvoice.suppliers)?.name || "مورد"}
                  {detailInvoice.supplier_invoice_number
                    ? ` • فاتورة المورد ${detailInvoice.supplier_invoice_number}`
                    : ""}
                </span>
                <h2 id="purchase-detail-title">
                  {detailInvoice.invoice_number}
                </h2>
                <p className="muted">
                  {detailInvoice.invoice_date}
                  {detailInvoice.due_date
                    ? ` • الاستحقاق ${detailInvoice.due_date}`
                    : ""}
                </p>
              </div>
              <button
                type="button"
                className="closeButton"
                aria-label="إغلاق"
                onClick={() => setDetailInvoice(null)}
              >
                ×
              </button>
            </div>

            {detailMessage ? <p className="muted">{detailMessage}</p> : null}

            {detailLines.length ? (
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>الصنف</th>
                      <th>الكمية</th>
                      <th>السعر</th>
                      <th>الخصم</th>
                      <th>الإجمالي</th>
                      <th>المستلم</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detailLines.map((line) => {
                      const product = oneRelation(line.products);
                      const quantity = Number(line.quantity);
                      return (
                        <tr key={line.id}>
                          <td>
                            <strong>{product?.name || "صنف"}</strong>
                            {line.notes ? (
                              <div className="muted">{line.notes}</div>
                            ) : null}
                          </td>
                          <td>
                            {formatQty(quantity)} {product?.unit || ""}
                          </td>
                          <td>
                            {money(line.unit_cost, detailInvoice.currency)}
                          </td>
                          <td>
                            {Number(line.discount_amount) > 0
                              ? money(
                                  line.discount_amount,
                                  detailInvoice.currency,
                                )
                              : "—"}
                          </td>
                          <td>
                            <strong>
                              {money(line.line_total, detailInvoice.currency)}
                            </strong>
                          </td>
                          <td>
                            {line.received == null ? (
                              "—"
                            ) : (
                              <span
                                className={`chip ${line.received >= quantity ? "green" : line.received > 0 ? "orange" : "gray"}`}
                              >
                                {line.received >= quantity
                                  ? "استلمنا الكل"
                                  : `${formatQty(line.received)} من ${formatQty(quantity)}`}
                              </span>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            ) : null}

            <div className="modalActions">
              <span className="muted">
                الإجمالي {money(detailInvoice.total, detailInvoice.currency)} •
                المدفوع{" "}
                {money(detailInvoice.paid_total, detailInvoice.currency)} •
                الباقي{" "}
                {money(detailInvoice.balance_due, detailInvoice.currency)}
              </span>
              <button
                type="button"
                className="softButton"
                onClick={() => setDetailInvoice(null)}
              >
                إغلاق
              </button>
            </div>
          </section>
        </div>
      ) : null}

      {cancelTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <h2>إلغاء فاتورة شراء</h2>
            </div>

            <form onSubmit={saveCancel}>
              <p>
                الفاتورة: <strong>{cancelTarget.invoice_number}</strong>
              </p>

              <label className="field">
                <span>سبب الإلغاء *</span>

                <textarea
                  value={cancelReason}
                  onChange={(event) => setCancelReason(event.target.value)}
                />
              </label>

              {cancelMessage ? (
                <div className="toastError">{cancelMessage}</div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={cancelling}
                  onClick={() => setCancelTarget(null)}
                >
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

      {reverseTarget ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <h2>عكس دفعة مورد</h2>
            </div>

            <form onSubmit={saveReverse}>
              <p>
                الدفعة: <strong>{reverseTarget.payment_number}</strong>
              </p>

              <label className="field">
                <span>سبب العكس *</span>

                <textarea
                  value={reverseReason}
                  onChange={(event) => setReverseReason(event.target.value)}
                />
              </label>

              {reverseMessage ? (
                <div className="toastError">{reverseMessage}</div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={reversing}
                  onClick={() => setReverseTarget(null)}
                >
                  رجوع
                </button>

                <button className="dangerButton" disabled={reversing}>
                  {reversing ? "جارٍ العكس..." : "تأكيد العكس"}
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
