"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Icons } from "@/components/icons";

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
  created_at: string;
  suppliers:
    | InvoiceSupplier
    | InvoiceSupplier[]
    | null;
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
  suppliers:
    | PaymentSupplier
    | PaymentSupplier[]
    | null;
  cashboxes:
    | PaymentCashbox
    | PaymentCashbox[]
    | null;
};

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
  orderId: string | null;
};

type PaymentMethod =
  | "cash"
  | "bank"
  | "card"
  | "check"
  | "other";

const paymentMethodLabels: Record<
  PaymentMethod,
  string
> = {
  cash: "نقدي",
  bank: "تحويل بنكي",
  card: "بطاقة",
  check: "شيك",
  other: "أخرى",
};

function oneRelation<T>(
  value: T | T[] | null
) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

function newKey() {
  return crypto.randomUUID();
}

function today() {
  return new Date()
    .toISOString()
    .slice(0, 10);
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
    orderId: null,
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
}) {
  const [supabase] = useState(
    () => createClient()
  );

  const router = useRouter();

  const [invoices, setInvoices] =
    useState(initialInvoices);

  const [payments, setPayments] =
    useState(initialPayments);

  const [message, setMessage] =
    useState(initialError || "");

  const [saving, setSaving] =
    useState(false);

  const [busyInvoice, setBusyInvoice] =
    useState<string | null>(null);

  const [busyPayment, setBusyPayment] =
    useState<string | null>(null);

  // ======================================================
  // PURCHASE INVOICE FORM
  // ======================================================

  const [open, setOpen] =
    useState(false);

  const [supplierId, setSupplierId] =
    useState("");

  const [
    supplierInvoiceNumber,
    setSupplierInvoiceNumber,
  ] = useState("");

  const [invoiceDate, setInvoiceDate] =
    useState(today());

  const [dueDate, setDueDate] =
    useState("");

  const [invoiceNotes, setInvoiceNotes] =
    useState("");

  const [lines, setLines] =
    useState<DraftLine[]>([]);

  // ======================================================
  // SUPPLIER PAYMENT FORM
  // ======================================================

  const [paymentOpen, setPaymentOpen] =
    useState(false);

  const [
    paymentSupplierId,
    setPaymentSupplierId,
  ] = useState("");

  const [
    paymentCashboxId,
    setPaymentCashboxId,
  ] = useState(
    cashboxes[0]?.id || ""
  );

  const [paymentAmount, setPaymentAmount] =
    useState("");

  
  const [
    paymentCashAmount,
    setPaymentCashAmount,
  ] = useState("");

  const [
    paymentCashCurrency,
    setPaymentCashCurrency,
  ] = useState(currency);

  const [
    paymentInvoiceCurrency,
    setPaymentInvoiceCurrency,
  ] = useState(currency);

  const [
    paymentFxRate,
    setPaymentFxRate,
  ] = useState<number | null>(1);

  const [
    paymentQuoteError,
    setPaymentQuoteError,
  ] = useState("");

  const [paymentDate, setPaymentDate] =
    useState(today());

  const [
    paymentMethod,
    setPaymentMethod,
  ] = useState<PaymentMethod>("cash");

  const [
    paymentReference,
    setPaymentReference,
  ] = useState("");

  const [paymentNotes, setPaymentNotes] =
    useState("");

  const [
    paymentAllocations,
    setPaymentAllocations,
  ] = useState<Record<string, string>>({});

  // ======================================================
  // PRICE MAP
  // ======================================================

  const priceMap = useMemo(() => {
    const map =
      new Map<string, number>();

    for (const row of supplierPrices) {
      if (!row.available) continue;

      map.set(
        `${row.supplier_id}:${row.product_id}`,
        Number(row.purchase_price)
      );
    }

    return map;
  }, [supplierPrices]);

  // ======================================================
  // NEEDS
  // ======================================================

  const eligibleNeeds = useMemo(() => {
    if (!supplierId) return [];

    return needs;
  }, [needs, supplierId]);

  const selectedNeedIds = useMemo(
    () =>
      new Set(
        lines
          .map(
            (line) =>
              line.salesOrderItemId
          )
          .filter(
            (
              value
            ): value is string =>
              Boolean(value)
          )
      ),
    [lines]
  );

  // ======================================================
  // PURCHASE INVOICE TOTALS
  // ======================================================

  const totals = useMemo(() => {
    return lines.reduce(
      (result, line) => {
        const quantity =
          Number(line.quantity || 0);

        const unitCost =
          Number(line.unitCost || 0);

        const discount =
          Number(
            line.discountAmount || 0
          );

        const tax =
          Number(
            line.taxAmount || 0
          );

        const base =
          quantity * unitCost;

        const total =
          Math.max(
            base - discount + tax,
            0
          );

        return {
          subtotal:
            result.subtotal + base,

          discount:
            result.discount + discount,

          tax:
            result.tax + tax,

          total:
            result.total + total,
        };
      },
      {
        subtotal: 0,
        discount: 0,
        tax: 0,
        total: 0,
      }
    );
  }, [lines]);

  // ======================================================
  // PAYMENT TOTALS
  // ======================================================

  const paymentInvoices =
    useMemo(() => {
      if (!paymentSupplierId) {
        return [];
      }

      return invoices.filter(
        (invoice) => {
          const supplier =
            oneRelation(
              invoice.suppliers
            );

          return (
            invoice.status !==
              "cancelled" &&
            Number(
              invoice.balance_due
            ) > 0 &&
            supplier?.id ===
              paymentSupplierId
          );
        }
      );
    }, [
      invoices,
      paymentSupplierId,
    ]);

  const paymentAllocated =
    useMemo(() => {
      return Object.values(
        paymentAllocations
      ).reduce(
        (sum, value) =>
          sum +
          Number(value || 0),
        0
      );
    }, [paymentAllocations]);

  const paymentAmountNumber =
    Number(paymentAmount || 0);

  const paymentUnallocated =
    Math.max(
      paymentAmountNumber -
        paymentAllocated,
      0
    );


  useEffect(() => {
    let cancelled = false;

    async function refreshSupplierPaymentQuote() {
      if (
        !paymentCashboxId ||
        !paymentDate
      ) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        return;
      }

      const cashbox =
        cashboxes.find(
          (row) =>
            row.id ===
            paymentCashboxId
        );

      if (!cashbox) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        return;
      }

      const invoiceCurrency =
        paymentInvoices[0]
          ?.currency ?? currency;

      setPaymentCashCurrency(
        cashbox.currency
      );

      setPaymentInvoiceCurrency(
        invoiceCurrency
      );

      if (
        paymentInvoices.some(
          (invoice) =>
            invoice.currency !==
            invoiceCurrency
        )
      ) {
        setPaymentCashAmount("");
        setPaymentQuoteError(
          "لا يمكن دفع فواتير بعملات مختلفة ضمن نفس الدفعة."
        );
        return;
      }

      const invoiceAmount =
        Number(
          paymentAmount || 0
        );

      if (
        !Number.isFinite(
          invoiceAmount
        ) ||
        invoiceAmount <= 0
      ) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        return;
      }

      if (
        cashbox.currency ===
        invoiceCurrency
      ) {
        setPaymentCashAmount(
          invoiceAmount.toFixed(2)
        );
        setPaymentFxRate(1);
        setPaymentQuoteError("");
        return;
      }

      const {
        data,
        error,
      } = await supabase.rpc(
        "payment_currency_quote",
        {
          target_company:
            companyId,

          target_invoice_currency:
            invoiceCurrency,

          target_payment_currency:
            cashbox.currency,

          target_invoice_amount:
            invoiceAmount,

          target_payment_date:
            paymentDate,
        }
      );

      if (cancelled) {
        return;
      }

      if (error) {
        setPaymentCashAmount("");
        setPaymentFxRate(null);
        setPaymentQuoteError(
          error.message
        );
        return;
      }

      const quote =
        Array.isArray(data)
          ? data[0]
          : data;

      const quotedAmount =
        Number(
          quote?.payment_amount ??
            0
        );

      const quotedRate =
        Number(
          quote?.payment_rate_to_base ??
            0
        );

      if (
        !Number.isFinite(
          quotedAmount
        ) ||
        quotedAmount <= 0
      ) {
        setPaymentCashAmount("");
        setPaymentFxRate(null);
        setPaymentQuoteError(
          "تعذر حساب مبلغ الصندوق."
        );
        return;
      }

      setPaymentCashAmount(
        quotedAmount.toFixed(2)
      );

      setPaymentFxRate(
        Number.isFinite(
          quotedRate
        ) &&
          quotedRate > 0
          ? quotedRate
          : null
      );

      setPaymentQuoteError("");
    }

    void refreshSupplierPaymentQuote();

    return () => {
      cancelled = true;
    };
  }, [
    paymentCashboxId,
    paymentDate,
    paymentAmount,
    paymentInvoices,
    cashboxes,
    companyId,
    currency,
    supabase,
  ]);
  const unpaidTotal = useMemo(
    () =>
      invoices
        .filter(
          (invoice) =>
            invoice.status !==
            "cancelled"
        )
        .reduce(
          (sum, invoice) =>
            sum +
            Number(
              invoice.balance_due || 0
            ),
          0
        ),
    [invoices]
  );

  const supplierCreditTotal =
    useMemo(
      () =>
        payments
          .filter(
            (payment) =>
              payment.status ===
              "posted"
          )
          .reduce(
            (sum, payment) =>
              sum +
              Number(
                payment.unallocated_total ||
                  0
              ) *
                Number(
                  payment.exchange_rate_to_base ||
                    1
                ),
            0
          ),
      [payments]
    );

  const remainingUnits =
    useMemo(
      () =>
        needs.reduce(
          (sum, need) =>
            sum +
            Number(
              need.remaining_quantity ||
                0
            ),
          0
        ),
      [needs]
    );

  // ======================================================
  // PURCHASE INVOICE HELPERS
  // ======================================================

  function priceForProduct(
    productId: string
  ) {
    if (
      !supplierId ||
      !productId
    ) {
      return null;
    }

    return (
      priceMap.get(
        `${supplierId}:${productId}`
      ) ?? null
    );
  }

  function resetInvoiceForm() {
    setSupplierId("");
    setSupplierInvoiceNumber("");
    setDueDate("");
    setInvoiceNotes("");
    setLines([]);
    setMessage("");
    setInvoiceDate(today());
  }

  function startInvoice() {
    resetInvoiceForm();
    setOpen(true);
  }

  function changeSupplier(
    value: string
  ) {
    if (
      lines.length > 0 &&
      value !== supplierId
    ) {
      const confirmed =
        window.confirm(
          "تغيير المورد سيحذف البنود الموجودة في الفاتورة الحالية. متابعة؟"
        );

      if (!confirmed) return;
    }

    setSupplierId(value);
    setLines([]);
    setMessage("");
  }

  function addNeed(
    need: PurchaseNeed
  ) {
    if (!supplierId) {
      setMessage(
        "اختار المورد أولًا."
      );
      return;
    }

    

    if (
      selectedNeedIds.has(
        need.sales_order_item_id
      )
    ) {
      return;
    }

    const currentPrice =
      priceForProduct(
        need.product_id
      );

    const unitCost =
      currentPrice ?? 0;

    setLines((current) => [
      ...current,
      {
        key: newKey(),
        productId:
          need.product_id,

        quantity: String(
          Number(
            need.remaining_quantity
          )
        ),

        unitCost:
          String(unitCost),

        discountAmount: "0",
        taxAmount: "0",
        notes: "",

        salesOrderItemId:
          need.sales_order_item_id,

        maxQuantity:
          Number(
            need.remaining_quantity
          ),

        traderName:
          need.trader_name || null,

        orderId:
          need.order_id,
      },
    ]);

    setMessage("");
  }

  function addManualLine() {
    if (!supplierId) {
      setMessage(
        "اختار المورد أولًا."
      );
      return;
    }

    setLines((current) => [
      ...current,
      emptyManualLine(),
    ]);

    setMessage("");
  }

  function removeLine(
    key: string
  ) {
    setLines((current) =>
      current.filter(
        (line) =>
          line.key !== key
      )
    );
  }

  function updateLine(
    key: string,
    patch: Partial<DraftLine>
  ) {
    setLines((current) =>
      current.map((line) =>
        line.key === key
          ? {
              ...line,
              ...patch,
            }
          : line
      )
    );
  }

  function chooseManualProduct(
    line: DraftLine,
    productId: string
  ) {
    const currentPrice =
      supplierId
        ? priceMap.get(
            `${supplierId}:${productId}`
          ) ?? null
        : null;

    updateLine(line.key, {
      productId,

      unitCost:
        currentPrice != null
          ? String(currentPrice)
          : "",
    });
  }

  async function saveInvoice(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();
    setMessage("");

    if (!supplierId) {
      setMessage(
        "اختار المورد."
      );
      return;
    }

    if (!invoiceDate) {
      setMessage(
        "تاريخ الفاتورة مطلوب."
      );
      return;
    }

    if (
      dueDate &&
      dueDate < invoiceDate
    ) {
      setMessage(
        "تاريخ الاستحقاق لا يمكن أن يكون قبل تاريخ الفاتورة."
      );
      return;
    }

    if (!lines.length) {
      setMessage(
        "أضف بندًا واحدًا على الأقل للفاتورة."
      );
      return;
    }

    for (const line of lines) {
      const quantity =
        Number(line.quantity);

      const unitCost =
        Number(line.unitCost);

      const discount =
        Number(
          line.discountAmount || 0
        );

      const tax =
        Number(
          line.taxAmount || 0
        );

      if (!line.productId) {
        setMessage(
          "يوجد بند بدون صنف."
        );
        return;
      }

      if (
        !Number.isFinite(
          quantity
        ) ||
        quantity <= 0
      ) {
        setMessage(
          "راجع كميات الفاتورة."
        );
        return;
      }

      if (
        line.maxQuantity !=
          null &&
        quantity >
          line.maxQuantity
      ) {
        setMessage(
          `الكمية أكبر من المتبقي لطلب التاجر ${line.traderName || ""}.`
        );
        return;
      }

      if (
        !Number.isFinite(
          unitCost
        ) ||
        unitCost < 0
      ) {
        setMessage(
          "راجع أسعار الشراء."
        );
        return;
      }

      if (
        !Number.isFinite(
          discount
        ) ||
        discount < 0 ||
        !Number.isFinite(tax) ||
        tax < 0
      ) {
        setMessage(
          "راجع الخصم والضريبة."
        );
        return;
      }
    }

    const payload =
      lines.map((line) => ({
        product_id:
          line.productId,

        quantity:
          Number(line.quantity),

        unit_cost:
          Number(line.unitCost),

        discount_amount:
          Number(
            line.discountAmount ||
              0
          ),

        tax_amount:
          Number(
            line.taxAmount || 0
          ),

        notes:
          line.notes.trim() ||
          null,

        allocations:
          line.salesOrderItemId
            ? [
                {
                  sales_order_item_id:
                    line.salesOrderItemId,

                  quantity:
                    Number(
                      line.quantity
                    ),
                },
              ]
            : [],
      }));

    setSaving(true);

    const { error } =
      await supabase.rpc(
        "create_purchase_invoice",
        {
          target_company:
            companyId,

          target_supplier:
            supplierId,

          target_supplier_invoice_number:
            supplierInvoiceNumber.trim() ||
            null,

          target_invoice_date:
            invoiceDate,

          target_due_date:
            dueDate || null,

          target_notes:
            invoiceNotes.trim() ||
            null,

          items_payload:
            payload,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setOpen(false);
    resetInvoiceForm();

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }

  // ======================================================
  // SUPPLIER PAYMENT HELPERS
  // ======================================================

  function resetPaymentForm() {
    setPaymentSupplierId("");
    setPaymentCashboxId(
      cashboxes[0]?.id || ""
    );
    setPaymentAmount("");
    setPaymentDate(today());
    setPaymentMethod("cash");
    setPaymentReference("");
    setPaymentNotes("");
    setPaymentAllocations({});
    setMessage("");
  }

  function startPayment(
    invoice?: PurchaseInvoiceRow
  ) {
    resetPaymentForm();

    if (invoice) {
      const supplier =
        oneRelation(
          invoice.suppliers
        );

      const balance =
        Number(
          invoice.balance_due ||
            0
        );

      setPaymentSupplierId(
        supplier?.id || ""
      );

      if (balance > 0) {
        setPaymentAmount(
          balance.toFixed(2)
        );

        setPaymentAllocations({
          [invoice.id]:
            balance.toFixed(2),
        });
      }
    }

    setPaymentOpen(true);
  }

  function changePaymentSupplier(
    value: string
  ) {
    if (
      Object.keys(
        paymentAllocations
      ).length > 0
    ) {
      const confirmed =
        window.confirm(
          "تغيير المورد سيحذف توزيع الدفعة الحالي. متابعة؟"
        );

      if (!confirmed) return;
    }

    setPaymentSupplierId(
      value
    );

    setPaymentAllocations(
      {}
    );
  }

  function setAllocation(
    invoiceId: string,
    value: string
  ) {
    setPaymentAllocations(
      (current) => ({
        ...current,
        [invoiceId]: value,
      })
    );
  }

  function allocateFullInvoice(
    invoice: PurchaseInvoiceRow
  ) {
    const balance =
      Number(
        invoice.balance_due ||
          0
      );

    const currentOther =
      Object.entries(
        paymentAllocations
      ).reduce(
        (
          sum,
          [id, value]
        ) =>
          id === invoice.id
            ? sum
            : sum +
              Number(
                value || 0
              ),
        0
      );

    const available =
      Math.max(
        Number(
          paymentAmount || 0
        ) - currentOther,
        0
      );

    const value =
      Math.min(
        balance,
        available
      );

    setAllocation(
      invoice.id,
      value > 0
        ? value.toFixed(2)
        : ""
    );
  }

  async function savePayment(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();
    setMessage("");

    const amount =
      Number(paymentAmount);

    
    const selectedCashbox =
      cashboxes.find(
        (cashbox) =>
          cashbox.id ===
          paymentCashboxId
      );

    const invoiceCurrencyForPayment =
      paymentInvoices[0]
        ?.currency ?? currency;

    const cashAmount =
      selectedCashbox?.currency ===
      invoiceCurrencyForPayment
        ? amount
        : Number(
            paymentCashAmount
          );

    if (!paymentSupplierId) {
      setMessage(
        "اختار المورد."
      );
      return;
    }

    if (!paymentCashboxId) {
      setMessage(
        "ما في صندوق مالي نشط مختار."
      );
      return;
    }

    if (
      !Number.isFinite(
        amount
      ) ||
      amount <= 0
    ) {
      setMessage(
        "اكتب مبلغ دفعة صحيح."
      );
      return;
    }

    if (
      paymentAllocated >
      amount + 0.001
    ) {
      setMessage(
        "مجموع توزيع الدفعة أكبر من مبلغ الدفعة."
      );
      return;
    }


    if (!selectedCashbox) {
      setMessage(
        "الصندوق المختار غير صالح."
      );
      return;
    }

    if (paymentQuoteError) {
      setMessage(
        paymentQuoteError
      );
      return;
    }

    if (
      selectedCashbox.currency !==
        invoiceCurrencyForPayment &&
      Math.abs(
        paymentAllocated -
          amount
      ) > 0.01
    ) {
      setMessage(
        "عند الدفع بعملة مختلفة لازم توزع كامل مبلغ الدفعة على الفواتير."
      );
      return;
    }

    if (
      !Number.isFinite(
        cashAmount
      ) ||
      cashAmount <= 0
    ) {
      setMessage(
        "تعذر حساب المبلغ بعملة الصندوق."
      );
      return;
    }
    const allocations: Array<{
      purchase_invoice_id: string;
      amount: number;
    }> = [];

    for (
      const invoice of
        paymentInvoices
    ) {
      const value =
        Number(
          paymentAllocations[
            invoice.id
          ] || 0
        );

      if (value <= 0) {
        continue;
      }

      if (
        !Number.isFinite(
          value
        )
      ) {
        setMessage(
          "راجع توزيع الدفعات."
        );
        return;
      }

      if (
        value >
        Number(
          invoice.balance_due
        ) +
          0.001
      ) {
        setMessage(
          `المبلغ الموزع على ${invoice.invoice_number} أكبر من رصيد الفاتورة.`
        );
        return;
      }

      allocations.push({
        purchase_invoice_id:
          invoice.id,
        amount: value,
      });
    }

    setSaving(true);

    const { error } =
      await supabase.rpc(
        "record_supplier_payment",
        {
          target_company:
            companyId,

          target_supplier:
            paymentSupplierId,

          target_cashbox:
            paymentCashboxId,

          target_amount:
            cashAmount,

          target_payment_date:
            paymentDate,

          target_method:
            paymentMethod,

          target_reference:
            paymentReference.trim() ||
            null,

          target_notes:
            paymentNotes.trim() ||
            null,

          allocations_payload:
            allocations,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setPaymentOpen(false);
    resetPaymentForm();

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }

  async function reversePayment(
    payment: SupplierPaymentRow
  ) {
    const reason =
      window.prompt(
        `سبب عكس الدفعة ${payment.payment_number}:`
      );

    if (reason === null) {
      return;
    }

    if (!reason.trim()) {
      window.alert(
        "اكتب سبب عكس الدفعة."
      );
      return;
    }

    const confirmed =
      window.confirm(
        `سيتم عكس دفعة بقيمة ${Number(
          payment.amount
        ).toFixed(2)} ${currency} وإرجاع أثرها المالي. متابعة؟`
      );

    if (!confirmed) {
      return;
    }

    setBusyPayment(
      payment.id
    );

    const { error } =
      await supabase.rpc(
        "reverse_supplier_payment",
        {
          target_company:
            companyId,

          target_payment:
            payment.id,

          target_reason:
            reason.trim(),
        }
      );

    setBusyPayment(null);

    if (error) {
      window.alert(
        error.message
      );
      return;
    }

    setPayments(
      (current) =>
        current.map((row) =>
          row.id ===
          payment.id
            ? {
                ...row,
                status:
                  "reversed",
                reversal_reason:
                  reason.trim(),
              }
            : row
        )
    );

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }

  async function cancelInvoice(
    invoice: PurchaseInvoiceRow
  ) {
    const reason =
      window.prompt(
        `سبب إلغاء الفاتورة ${invoice.invoice_number}:`
      );

    if (reason === null) {
      return;
    }

    if (!reason.trim()) {
      window.alert(
        "اكتب سبب الإلغاء."
      );
      return;
    }

    const confirmed =
      window.confirm(
        "سيتم إلغاء الفاتورة وإعادة احتياجات الشراء المرتبطة بها. متابعة؟"
      );

    if (!confirmed) {
      return;
    }

    setBusyInvoice(
      invoice.id
    );

    const { error } =
      await supabase.rpc(
        "cancel_purchase_invoice",
        {
          target_company:
            companyId,

          target_invoice:
            invoice.id,

          target_reason:
            reason.trim(),
        }
      );

    setBusyInvoice(null);

    if (error) {
      window.alert(
        error.message
      );
      return;
    }

    setInvoices(
      (current) =>
        current.map((row) =>
          row.id ===
          invoice.id
            ? {
                ...row,
                status:
                  "cancelled",
              }
            : row
        )
    );

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }

  // ======================================================
  // UI
  // ======================================================

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            دورة الشراء
          </span>

          <h2>
            المشتريات والموردون
          </h2>

          <p className="muted">
            احتياجات الشراء، فواتير
            الموردين، الدفعات والرصيد
            المستحق.
          </p>
        </div>

        <div className="rowActions">
          <button
            type="button"
            className="softButton"
            onClick={() =>
              startPayment()
            }
          >
            <Icons.money
              size={15}
            />
            دفع لمورد
          </button>

          <button
            type="button"
            className="primaryButton"
            onClick={startInvoice}
          >
            <Icons.plus
              size={15}
            />
            فاتورة شراء جديدة
          </button>
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="بنود مطلوبة"
          value={String(
            needs.length
          )}
        />

        <Mini
          title="كميات متبقية"
          value={remainingUnits.toFixed(
            3
          )}
        />

        <Mini
          title="مستحق للموردين"
          value={`${unpaidTotal.toFixed(
            2
          )} ${currency}`}
        />

        <Mini
          title="دفعات مقدمة"
          value={`${supplierCreditTotal.toFixed(
            2
          )} ${currency}`}
        />
      </section>

      {message &&
      !open &&
      !paymentOpen ? (
        <div
          className="toastError"
          style={{
            marginTop: 14,
          }}
        >
          {message}
        </div>
      ) : null}

      <section
        className="panel panelPad"
        style={{
          marginTop: 14,
        }}
      >
        <div className="panelHeader">
          <div>
            <h2>
              احتياجات الشراء المفتوحة
            </h2>

            <p>
              المطلوب والمتبقي من
              طلبيات التجار.
            </p>
          </div>
        </div>

        {!needs.length ? (
          <div className="empty">
            <Icons.check
              size={30}
            />

            <h3>
              ما في احتياجات شراء
            </h3>

            <p>
              كل البنود الحالية تم
              شراؤها.
            </p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الصنف</th>
                  <th>التاجر</th>
                  <th>المورد</th>
                  <th>المطلوب</th>
                  <th>تم شراؤه</th>
                  <th>المتبقي</th>
                  <th>الكلفة</th>
                </tr>
              </thead>

              <tbody>
                {needs.map(
                  (need) => (
                    <tr
                      key={
                        need.sales_order_item_id
                      }
                    >
                      <td>
                        <strong>
                          {
                            need.product_name
                          }
                        </strong>

                        <div className="muted">
                          {need.sku ||
                            "—"}
                        </div>
                      </td>

                      <td>
                        {
                          need.trader_name
                        }
                      </td>

                      <td>
                        {"يحدد عند الشراء"}
                      </td>

                      <td>
                        {Number(
                          need.required_quantity
                        )}
                      </td>

                      <td>
                        {Number(
                          need.allocated_quantity
                        )}
                      </td>

                      <td>
                        <strong>
                          {Number(
                            need.remaining_quantity
                          )}
                        </strong>
                      </td>

                      <td>
                        <span className="muted">يحدد عند الشراء</span>
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section
        className="panel panelPad"
        style={{
          marginTop: 14,
        }}
      >
        <div className="panelHeader">
          <div>
            <h2>
              فواتير الشراء
            </h2>

            <p>
              الفواتير، المدفوع
              والمتبقي لكل مورد.
            </p>
          </div>
        </div>

        {!invoices.length ? (
          <div className="empty">
            <Icons.store
              size={28}
            />

            <h3>
              ما في فواتير شراء
            </h3>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>رقم الفاتورة</th>
                  <th>المورد</th>
                  <th>رقم المورد</th>
                  <th>التاريخ</th>
                  <th>الإجمالي</th>
                  <th>المدفوع</th>
                  <th>المتبقي</th>
                  <th>الحالة</th>
                  <th>إجراءات</th>
                </tr>
              </thead>

              <tbody>
                {invoices.map(
                  (invoice) => {
                    const supplier =
                      oneRelation(
                        invoice.suppliers
                      );

                    return (
                      <tr
                        key={
                          invoice.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              invoice.invoice_number
                            }
                          </strong>
                        </td>

                        <td>
                          {supplier?.name ||
                            "—"}
                        </td>

                        <td>
                          {invoice.supplier_invoice_number ||
                            "—"}
                        </td>

                        <td>
                          {
                            invoice.invoice_date
                          }
                        </td>

                        <td>
                          {Number(
                            invoice.total
                          ).toFixed(
                            2
                          )}{" "}
                          {invoice.currency}
                        </td>

                        <td>
                          {Number(
                            invoice.paid_total
                          ).toFixed(
                            2
                          )}{" "}
                          {invoice.currency}
                        </td>

                        <td>
                          <strong>
                            {Number(
                              invoice.balance_due
                            ).toFixed(
                              2
                            )}{" "}
                            {
                              invoice.currency
                            }
                          </strong>
                        </td>

                        <td>
                          {invoice.status ===
                          "cancelled" ? (
                            <span className="chip gray">
                              ملغاة
                            </span>
                          ) : (
                            <span
                              className={`chip ${
                                invoice.payment_status ===
                                "paid"
                                  ? "green"
                                  : invoice.payment_status ===
                                      "partial"
                                    ? "orange"
                                    : "gray"
                              }`}
                            >
                              {invoice.payment_status ===
                              "paid"
                                ? "مدفوعة"
                                : invoice.payment_status ===
                                    "partial"
                                  ? "جزئي"
                                  : "غير مدفوعة"}
                            </span>
                          )}
                        </td>

                        <td>
                          <div className="rowActions">
                            {invoice.status !==
                              "cancelled" &&
                            Number(
                              invoice.balance_due
                            ) > 0 ? (
                              <button
                                type="button"
                                className="primaryButton"
                                onClick={() =>
                                  startPayment(
                                    invoice
                                  )
                                }
                              >
                                دفع
                              </button>
                            ) : null}

                            {invoice.status !==
                            "cancelled" ? (
                              <button
                                type="button"
                                className="dangerButton"
                                disabled={
                                  busyInvoice ===
                                  invoice.id
                                }
                                onClick={() =>
                                  void cancelInvoice(
                                    invoice
                                  )
                                }
                              >
                                إلغاء
                              </button>
                            ) : null}
                          </div>
                        </td>
                      </tr>
                    );
                  }
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section
        className="panel panelPad"
        style={{
          marginTop: 14,
        }}
      >
        <div className="panelHeader">
          <div>
            <h2>
              دفعات الموردين
            </h2>

            <p>
              كل دفعة محفوظة ويمكن
              عكسها بدون حذف السجل.
            </p>
          </div>
        </div>

        {!payments.length ? (
          <div className="empty">
            <Icons.money
              size={28}
            />

            <h3>
              ما في دفعات موردين
            </h3>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>رقم الدفعة</th>
                  <th>المورد</th>
                  <th>المبلغ</th>
                  <th>موزع</th>
                  <th>رصيد مقدم</th>
                  <th>الطريقة</th>
                  <th>الصندوق</th>
                  <th>التاريخ</th>
                  <th>الحالة</th>
                  <th>إجراء</th>
                </tr>
              </thead>

              <tbody>
                {payments.map(
                  (payment) => {
                    const supplier =
                      oneRelation(
                        payment.suppliers
                      );

                    const cashbox =
                      oneRelation(
                        payment.cashboxes
                      );

                    return (
                      <tr
                        key={
                          payment.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              payment.payment_number
                            }
                          </strong>

                          <div className="muted">
                            {payment.reference_number ||
                              ""}
                          </div>
                        </td>

                        <td>
                          {supplier?.name ||
                            "—"}
                        </td>

                        <td>
                          {Number(
                            payment.amount
                          ).toFixed(2)}{" "}
                          {payment.payment_currency ||
                            cashbox?.currency ||
                            currency}

                          {payment.payment_currency &&
                          payment.payment_currency !== currency &&
                          payment.base_amount != null ? (
                            <div className="muted">
                              ? {Number(
                                payment.base_amount
                              ).toFixed(2)}{" "}
                              {currency}
                            </div>
                          ) : null}
                        </td>

                        <td>
                          {Number(
                            payment.allocated_total
                          ).toFixed(2)}{" "}
                          {payment.payment_currency ||
                            cashbox?.currency ||
                            currency}
                        </td>

                        <td>
                          {Number(
                            payment.unallocated_total
                          ).toFixed(2)}{" "}
                          {payment.payment_currency ||
                            cashbox?.currency ||
                            currency}
                        </td>

                        <td>
                          {paymentMethodLabels[
                            payment.payment_method as PaymentMethod
                          ] ||
                            payment.payment_method}
                        </td>

                        <td>
                          {cashbox?.name ||
                            "—"}
                        </td>

                        <td>
                          {
                            payment.payment_date
                          }
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              payment.status ===
                              "posted"
                                ? "green"
                                : "gray"
                            }`}
                          >
                            {payment.status ===
                            "posted"
                              ? "مثبتة"
                              : "معكوسة"}
                          </span>
                        </td>

                        <td>
                          {payment.status ===
                          "posted" ? (
                            <button
                              type="button"
                              className="dangerButton"
                              disabled={
                                busyPayment ===
                                payment.id
                              }
                              onClick={() =>
                                void reversePayment(
                                  payment
                                )
                              }
                            >
                              عكس
                            </button>
                          ) : (
                            <span className="muted">
                              {payment.reversal_reason ||
                                "—"}
                            </span>
                          )}
                        </td>
                      </tr>
                    );
                  }
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {open ? (
        <div
          className="modalOverlay"
          onMouseDown={(
            event
          ) => {
            if (
              event.target ===
                event.currentTarget &&
              !saving
            ) {
              setOpen(false);
            }
          }}
        >
          <section
            className="modal"
            style={{
              maxWidth: 1100,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  فاتورة مورد
                </span>

                <h2>
                  فاتورة شراء جديدة
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setOpen(false)
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={saveInvoice}
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    المورد *
                  </span>

                  <select
                    value={
                      supplierId
                    }
                    onChange={(
                      event
                    ) =>
                      changeSupplier(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="">
                      اختر المورد
                    </option>

                    {suppliers.map(
                      (
                        supplier
                      ) => (
                        <option
                          key={
                            supplier.id
                          }
                          value={
                            supplier.id
                          }
                        >
                          {
                            supplier.name
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    رقم فاتورة المورد
                  </span>

                  <input
                    value={
                      supplierInvoiceNumber
                    }
                    onChange={(
                      event
                    ) =>
                      setSupplierInvoiceNumber(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    تاريخ الفاتورة
                  </span>

                  <input
                    type="date"
                    value={
                      invoiceDate
                    }
                    onChange={(
                      event
                    ) =>
                      setInvoiceDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    الاستحقاق
                  </span>

                  <input
                    type="date"
                    min={
                      invoiceDate
                    }
                    value={dueDate}
                    onChange={(
                      event
                    ) =>
                      setDueDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              {supplierId ? (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 15,
                  }}
                >
                  <div className="panelHeader">
                    <div>
                      <h2>
                        المطلوب من المورد
                      </h2>

                      <p>
                        أضف البنود المطلوبة
                        من طلبيات التجار.
                      </p>
                    </div>
                  </div>

                  {!eligibleNeeds.length ? (
                    <p className="muted">
                      ما في احتياجات شراء
                      حالية.
                    </p>
                  ) : (
                    <div className="tableWrap">
                      <table className="dataTable">
                        <thead>
                          <tr>
                            <th>
                              الصنف
                            </th>
                            <th>
                              التاجر
                            </th>
                            <th>
                              المتبقي
                            </th>
                            <th>
                              إضافة
                            </th>
                          </tr>
                        </thead>

                        <tbody>
                          {eligibleNeeds.map(
                            (
                              need
                            ) => (
                              <tr
                                key={
                                  need.sales_order_item_id
                                }
                              >
                                <td>
                                  {
                                    need.product_name
                                  }
                                </td>

                                <td>
                                  {
                                    need.trader_name
                                  }
                                </td>

                                <td>
                                  {Number(
                                    need.remaining_quantity
                                  )}
                                </td>

                                <td>
                                  <button
                                    type="button"
                                    className="softButton"
                                    disabled={selectedNeedIds.has(
                                      need.sales_order_item_id
                                    )}
                                    onClick={() =>
                                      addNeed(
                                        need
                                      )
                                    }
                                  >
                                    {selectedNeedIds.has(
                                      need.sales_order_item_id
                                    )
                                      ? "مضاف"
                                      : "إضافة"}
                                  </button>
                                </td>
                              </tr>
                            )
                          )}
                        </tbody>
                      </table>
                    </div>
                  )}
                </div>
              ) : null}

              <div
                className="panel panelPad"
                style={{
                  marginTop: 15,
                }}
              >
                <div className="panelHeader">
                  <div>
                    <h2>
                      بنود الفاتورة
                    </h2>
                  </div>

                  <button
                    type="button"
                    className="softButton"
                    onClick={
                      addManualLine
                    }
                  >
                    <Icons.plus
                      size={13}
                    />
                    بند يدوي
                  </button>
                </div>

                {!lines.length ? (
                  <p className="muted">
                    ما في بنود مضافة.
                  </p>
                ) : (
                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th>
                            الصنف
                          </th>
                          <th>
                            الكمية
                          </th>
                          <th>
                            الكلفة
                          </th>
                          <th>
                            الخصم
                          </th>
                          <th>
                            الضريبة
                          </th>
                          <th>
                            الإجمالي
                          </th>
                          <th />
                        </tr>
                      </thead>

                      <tbody>
                        {lines.map(
                          (line) => {
                            const quantity =
                              Number(
                                line.quantity ||
                                  0
                              );

                            const cost =
                              Number(
                                line.unitCost ||
                                  0
                              );

                            const discount =
                              Number(
                                line.discountAmount ||
                                  0
                              );

                            const tax =
                              Number(
                                line.taxAmount ||
                                  0
                              );

                            const total =
                              Math.max(
                                quantity *
                                  cost -
                                  discount +
                                  tax,
                                0
                              );

                            return (
                              <tr
                                key={
                                  line.key
                                }
                              >
                                <td>
                                  {line.salesOrderItemId ? (
                                    <>
                                      <strong>
                                        {
                                          products.find(
                                            (
                                              product
                                            ) =>
                                              product.id ===
                                              line.productId
                                          )?.name
                                        }
                                      </strong>

                                      <div className="muted">
                                        {line.traderName
                                          ? `للتاجر: ${line.traderName}`
                                          : ""}
                                      </div>
                                    </>
                                  ) : (
                                    <select
                                      value={
                                        line.productId
                                      }
                                      onChange={(
                                        event
                                      ) =>
                                        chooseManualProduct(
                                          line,
                                          event
                                            .target
                                            .value
                                        )
                                      }
                                    >
                                      <option value="">
                                        اختر
                                        الصنف
                                      </option>

                                      {products.map(
                                        (
                                          product
                                        ) => (
                                          <option
                                            key={
                                              product.id
                                            }
                                            value={
                                              product.id
                                            }
                                          >
                                            {
                                              product.name
                                            }
                                          </option>
                                        )
                                      )}
                                    </select>
                                  )}
                                </td>

                                <td>
                                  <input
                                    type="number"
                                    min="0.001"
                                    step="0.001"
                                    max={
                                      line.maxQuantity ??
                                      undefined
                                    }
                                    value={
                                      line.quantity
                                    }
                                    onChange={(
                                      event
                                    ) =>
                                      updateLine(
                                        line.key,
                                        {
                                          quantity:
                                            event
                                              .target
                                              .value,
                                        }
                                      )
                                    }
                                    style={{
                                      width: 95,
                                    }}
                                  />
                                </td>

                                <td>
                                  <input
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    value={
                                      line.unitCost
                                    }
                                    onChange={(
                                      event
                                    ) =>
                                      updateLine(
                                        line.key,
                                        {
                                          unitCost:
                                            event
                                              .target
                                              .value,
                                        }
                                      )
                                    }
                                    style={{
                                      width: 100,
                                    }}
                                  />
                                </td>

                                <td>
                                  <input
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    value={
                                      line.discountAmount
                                    }
                                    onChange={(
                                      event
                                    ) =>
                                      updateLine(
                                        line.key,
                                        {
                                          discountAmount:
                                            event
                                              .target
                                              .value,
                                        }
                                      )
                                    }
                                    style={{
                                      width: 85,
                                    }}
                                  />
                                </td>

                                <td>
                                  <input
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    value={
                                      line.taxAmount
                                    }
                                    onChange={(
                                      event
                                    ) =>
                                      updateLine(
                                        line.key,
                                        {
                                          taxAmount:
                                            event
                                              .target
                                              .value,
                                        }
                                      )
                                    }
                                    style={{
                                      width: 85,
                                    }}
                                  />
                                </td>

                                <td>
                                  {total.toFixed(
                                    2
                                  )}{" "}
                                  {currency}
                                </td>

                                <td>
                                  <button
                                    type="button"
                                    className="dangerButton"
                                    onClick={() =>
                                      removeLine(
                                        line.key
                                      )
                                    }
                                  >
                                    ×
                                  </button>
                                </td>
                              </tr>
                            );
                          }
                        )}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>

              <label
                className="field"
                style={{
                  marginTop: 15,
                }}
              >
                <span>
                  ملاحظات
                </span>

                <textarea
                  rows={3}
                  value={
                    invoiceNotes
                  }
                  onChange={(
                    event
                  ) =>
                    setInvoiceNotes(
                      event.target
                        .value
                    )
                  }
                />
              </label>

              <div
                className="panel panelPad"
                style={{
                  marginTop: 15,
                }}
              >
                <div className="panelHeader">
                  <div>
                    <h2>
                      إجمالي الفاتورة
                    </h2>

                    <p>
                      قبل الدفعات.
                    </p>
                  </div>

                  <div
                    style={{
                      textAlign: "end",
                    }}
                  >
                    <div className="muted">
                      الإجمالي قبل
                      الخصم:{" "}
                      {totals.subtotal.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>

                    <div className="muted">
                      الخصم:{" "}
                      {totals.discount.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>

                    <div className="muted">
                      الضريبة:{" "}
                      {totals.tax.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>

                    <div className="statValue">
                      {totals.total.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>
                  </div>
                </div>
              </div>

              {message ? (
                <div
                  className="toastError"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {message}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() =>
                    setOpen(false)
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving
                    ? "عم نثبت..."
                    : "تثبيت الفاتورة"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {paymentOpen ? (
        <div
          className="modalOverlay"
          onMouseDown={(
            event
          ) => {
            if (
              event.target ===
                event.currentTarget &&
              !saving
            ) {
              setPaymentOpen(
                false
              );
            }
          }}
        >
          <section
            className="modal"
            style={{
              maxWidth: 900,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  حساب المورد
                </span>

                <h2>
                  تسجيل دفعة مورد
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setPaymentOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                savePayment
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    المورد *
                  </span>

                  <select
                    value={
                      paymentSupplierId
                    }
                    onChange={(
                      event
                    ) =>
                      changePaymentSupplier(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="">
                      اختر المورد
                    </option>

                    {suppliers.map(
                      (
                        supplier
                      ) => (
                        <option
                          key={
                            supplier.id
                          }
                          value={
                            supplier.id
                          }
                        >
                          {
                            supplier.name
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    الصندوق *
                  </span>

                  <select
                    value={
                      paymentCashboxId
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentCashboxId(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="">
                      اختر الصندوق
                    </option>

                    {cashboxes.map(
                      (
                        cashbox
                      ) => (
                        <option
                          key={
                            cashbox.id
                          }
                          value={
                            cashbox.id
                          }
                        >
                          {cashbox.name} - {cashbox.currency}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    مبلغ الدفعة ({currency})
                    *
                  </span>

                  <input
                    type="number"
                    min="0.01"
                    step="0.01"
                    value={
                      paymentAmount
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentAmount(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    تاريخ الدفعة
                  </span>

                  <input
                    type="date"
                    value={
                      paymentDate
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    طريقة الدفع
                  </span>

                  <select
                    value={
                      paymentMethod
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentMethod(
                        event.target
                          .value as PaymentMethod
                      )
                    }
                  >
                    {Object.entries(
                      paymentMethodLabels
                    ).map(
                      ([
                        value,
                        label,
                      ]) => (
                        <option
                          key={
                            value
                          }
                          value={
                            value
                          }
                        >
                          {label}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    رقم المرجع
                  </span>

                  <input
                    value={
                      paymentReference
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentReference(
                        event.target
                          .value
                      )
                    }
                    placeholder="رقم تحويل / شيك..."
                  />
                </label>
              </div>

                            {paymentCashboxId &&
              Number(
                paymentAmount || 0
              ) > 0 ? (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 15,
                  }}
                >
                  {paymentQuoteError ? (
                    <div className="toastError">
                      {paymentQuoteError}
                    </div>
                  ) : (
                    <>
                      <div className="muted">
                        قيمة الدفعة على الفواتير:{" "}
                        {Number(
                          paymentAmount || 0
                        ).toFixed(2)}{" "}
                        {paymentInvoiceCurrency}
                      </div>

                      <div
                        className="statValue"
                        style={{
                          marginTop: 5,
                        }}
                      >
                        سيخرج من الصندوق:{" "}
                        {paymentCashAmount ||
                          "—"}{" "}
                        {paymentCashCurrency}
                      </div>

                      {paymentCashCurrency !==
                        paymentInvoiceCurrency &&
                      paymentFxRate ? (
                        <div
                          className="muted"
                          style={{
                            marginTop: 5,
                          }}
                        >
                          سعر العملية: 1{" "}
                          {paymentCashCurrency}
                          {" = "}
                          {paymentFxRate.toFixed(
                            10
                          )}{" "}
                          {currency}
                        </div>
                      ) : null}
                    </>
                  )}
                </div>
              ) : null}
{paymentSupplierId ? (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 15,
                  }}
                >
                  <div className="panelHeader">
                    <div>
                      <h2>
                        توزيع الدفعة
                      </h2>

                      <p>
                        وزّع كامل المبلغ
                        أو جزء منه على
                        الفواتير المفتوحة.
                      </p>
                    </div>
                  </div>

                  {!paymentInvoices.length ? (
                    <p className="muted">
                      ما في فواتير مستحقة
                      لهذا المورد. المبلغ
                      سيُحفظ كدفعة مقدمة.
                    </p>
                  ) : (
                    <div className="tableWrap">
                      <table className="dataTable">
                        <thead>
                          <tr>
                            <th>
                              الفاتورة
                            </th>
                            <th>
                              التاريخ
                            </th>
                            <th>
                              الرصيد
                            </th>
                            <th>
                              المبلغ
                              الموزع
                            </th>
                            <th />
                          </tr>
                        </thead>

                        <tbody>
                          {paymentInvoices.map(
                            (
                              invoice
                            ) => (
                              <tr
                                key={
                                  invoice.id
                                }
                              >
                                <td>
                                  <strong>
                                    {
                                      invoice.invoice_number
                                    }
                                  </strong>
                                </td>

                                <td>
                                  {
                                    invoice.invoice_date
                                  }
                                </td>

                                <td>
                                  {Number(
                                    invoice.balance_due
                                  ).toFixed(
                                    2
                                  )}{" "}
                                  {
                                    currency
                                  }
                                </td>

                                <td>
                                  <input
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    max={
                                      invoice.balance_due
                                    }
                                    value={
                                      paymentAllocations[
                                        invoice
                                          .id
                                      ] ||
                                      ""
                                    }
                                    onChange={(
                                      event
                                    ) =>
                                      setAllocation(
                                        invoice.id,
                                        event
                                          .target
                                          .value
                                      )
                                    }
                                    style={{
                                      width: 130,
                                    }}
                                  />
                                </td>

                                <td>
                                  <button
                                    type="button"
                                    className="softButton"
                                    onClick={() =>
                                      allocateFullInvoice(
                                        invoice
                                      )
                                    }
                                  >
                                    تعبئة
                                  </button>
                                </td>
                              </tr>
                            )
                          )}
                        </tbody>
                      </table>
                    </div>
                  )}
                </div>
              ) : null}

              <div
                className="panel panelPad"
                style={{
                  marginTop: 15,
                }}
              >
                <div className="panelHeader">
                  <div>
                    <h2>
                      ملخص الدفعة
                    </h2>
                  </div>

                  <div
                    style={{
                      textAlign: "end",
                    }}
                  >
                    <div className="muted">
                      مبلغ الدفعة:{" "}
                      {paymentAmountNumber.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>

                    <div className="muted">
                      موزع على
                      فواتير:{" "}
                      {paymentAllocated.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>

                    <div className="statValue">
                      رصيد مقدم:{" "}
                      {paymentUnallocated.toFixed(
                        2
                      )}{" "}
                      {currency}
                    </div>
                  </div>
                </div>
              </div>

              <label
                className="field"
                style={{
                  marginTop: 15,
                }}
              >
                <span>
                  ملاحظات الدفعة
                </span>

                <textarea
                  rows={3}
                  value={
                    paymentNotes
                  }
                  onChange={(
                    event
                  ) =>
                    setPaymentNotes(
                      event.target
                        .value
                    )
                  }
                />
              </label>

              {message ? (
                <div
                  className="toastError"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {message}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() =>
                    setPaymentOpen(
                      false
                    )
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving
                    ? "عم نسجل الدفعة..."
                    : "تسجيل الدفعة"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function Mini({
  title,
  value,
}: {
  title: string;
  value: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">
        {title}
      </div>

      <div className="statValue">
        {value}
      </div>
    </div>
  );
}



