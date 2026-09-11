"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";
import {
  useRouter,
  useSearchParams,
} from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Icons } from "@/components/icons";

type OrderStatus =
  | "draft"
  | "new"
  | "to_purchase"
  | "purchasing"
  | "ready"
  | "out_for_delivery"
  | "delivered"
  | "cancelled";

type PaymentStatus =
  | "unpaid"
  | "partial"
  | "paid"
  | "credit";

type PaymentMethod =
  | "cash"
  | "bank"
  | "card"
  | "check"
  | "other";

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
};

export type OrderSalesInvoice = {
  id: string;
  order_id: string;
  trader_id: string;
  invoice_number: string;
    currency: string;
total: number;
  paid_total: number;
  balance_due: number;
  payment_status:
    | "unpaid"
    | "partial"
    | "paid";
  status: "posted" | "cancelled";
};

export type OrderCashbox = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
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
  products:
    | ProductRelation
    | ProductRelation[]
    | null;
};

export type OrderRow = {
  id: string;
  trader_id: string;
  status: OrderStatus;
  payment_status: PaymentStatus;
  subtotal: number;
  total: number;
  notes: string | null;
  created_at: string;
  delivered_at: string | null;
  traders:
    | TraderRelation
    | TraderRelation[]
    | null;
  sales_order_items: OrderItem[];
};

type ItemDraft = {
  key: string;
  product_id: string;
  quantity: string;
  sale_unit_price: string;
};

type CollectionState = {
  order: OrderRow;
  invoices: OrderSalesInvoice[];
};

const statusLabels: Record<
  OrderStatus,
  string
> = {
  draft: "Ù…Ø³ÙˆØ¯Ø©",
  new: "Ø¬Ø¯ÙŠØ¯",
  to_purchase: "Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„ØªÙˆÙÙŠØ±",
  purchasing: "Ù‚ÙŠØ¯ Ø§Ù„ØªÙˆÙÙŠØ±",
  ready: "Ø¬Ø§Ù‡Ø²",
  out_for_delivery: "Ø¨Ø§Ù„ØªÙˆØµÙŠÙ„",
  delivered: "ØªÙ… Ø§Ù„ØªØ³Ù„ÙŠÙ…",
  cancelled: "Ù…Ù„ØºÙŠ",
};

function emptyItem(): ItemDraft {
  return {
    key: crypto.randomUUID(),
    product_id: "",
    quantity: "1",
    sale_unit_price: "",
  };
}

function oneRelation<T>(
  value: T | T[] | null
) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

function localDateInput() {
  const now = new Date();

  const year = now.getFullYear();
  const month = String(
    now.getMonth() + 1
  ).padStart(2, "0");
  const day = String(
    now.getDate()
  ).padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function paymentLabel(
  status: PaymentStatus
) {
  if (status === "paid") {
    return "Ù…Ø¯ÙÙˆØ¹";
  }

  if (status === "partial") {
    return "Ø¬Ø²Ø¦ÙŠ";
  }

  if (status === "credit") {
    return "Ø¢Ø¬Ù„";
  }

  return "ØºÙŠØ± Ù…Ø¯ÙÙˆØ¹";
}

export function OrdersClient({
  companyId,
  currency,
  initialOrders,
  traders,
  products,
  invoices,
  cashboxes,
  canCreate,
  canCancel,
  canCollect,
}: {
  companyId: string;
  currency: string;
  initialOrders: OrderRow[];
  traders: OrderTrader[];
  products: OrderProduct[];
  invoices: OrderSalesInvoice[];
  cashboxes: OrderCashbox[];
  canCreate: boolean;
  canCancel: boolean;
  canCollect: boolean;
}) {
  const [supabase] = useState(
    () => createClient()
  );

  const router = useRouter();
  const searchParams = useSearchParams();

  const [orders, setOrders] =
    useState<OrderRow[]>(initialOrders);

  const [open, setOpen] =
    useState(false);

  const [trader, setTrader] =
    useState("");

  const [items, setItems] =
    useState<ItemDraft[]>([
      emptyItem(),
    ]);

  const [notes, setNotes] =
    useState("");

  const [saving, setSaving] =
    useState(false);

  const [message, setMessage] =
    useState("");

  const [
    collection,
    setCollection,
  ] = useState<CollectionState | null>(
    null
  );

  const [
    paymentAmount,
    setPaymentAmount,
  ] = useState("");

  
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
  ] = useState("");const [
    paymentDate,
    setPaymentDate,
  ] = useState(localDateInput());

  const [
    paymentMethod,
    setPaymentMethod,
  ] =
    useState<PaymentMethod>("cash");

  const [
    paymentCashbox,
    setPaymentCashbox,
  ] = useState("");

  const [
    paymentReference,
    setPaymentReference,
  ] = useState("");

  const [
    paymentNotes,
    setPaymentNotes,
  ] = useState("");

  const [
    paymentMessage,
    setPaymentMessage,
  ] = useState("");

  const [
    collecting,
    setCollecting,
  ] = useState(false);

  useEffect(() => {
    setOrders(initialOrders);
  }, [initialOrders]);


  useEffect(() => {
    let cancelled = false;

    async function refreshPaymentCurrencyQuote() {
      if (
        !collection ||
        !paymentCashbox ||
        !paymentDate
      ) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        return;
      }

      const invoiceCurrency =
        collection.invoices[0]
          ?.currency ?? currency;

      setPaymentInvoiceCurrency(
        invoiceCurrency
      );

      if (
        collection.invoices.some(
          (invoice) =>
            invoice.currency !==
            invoiceCurrency
        )
      ) {
        setPaymentCashAmount("");
        setPaymentFxRate(null);
        setPaymentQuoteError(
          "Ù„Ø§ ÙŠÙ…ÙƒÙ† Ù‚Ø¨Ø¶ ÙÙˆØ§ØªÙŠØ± Ø¨Ø¹Ù…Ù„Ø§Øª Ù…Ø®ØªÙ„ÙØ© Ø¶Ù…Ù† Ù†ÙØ³ Ø§Ù„Ø¹Ù…Ù„ÙŠØ©."
        );
        return;
      }

      const selectedCashbox =
        cashboxes.find(
          (cashbox) =>
            cashbox.id ===
            paymentCashbox
        );

      if (!selectedCashbox) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        return;
      }

      setPaymentCashCurrency(
        selectedCashbox.currency
      );

      const invoiceAmount =
        Number(paymentAmount || 0);

      if (
        !Number.isFinite(invoiceAmount) ||
        invoiceAmount <= 0
      ) {
        setPaymentCashAmount("");
        setPaymentQuoteError("");
        return;
      }

      if (
        selectedCashbox.currency ===
        invoiceCurrency
      ) {
        setPaymentCashAmount(
          invoiceAmount.toFixed(2)
        );
        setPaymentFxRate(1);
        setPaymentQuoteError("");
        return;
      }

      const { data, error } =
        await supabase.rpc(
          "payment_currency_quote",
          {
            target_company:
              companyId,

            target_invoice_currency:
              invoiceCurrency,

            target_payment_currency:
              selectedCashbox.currency,

            target_invoice_amount:
              invoiceAmount,

            target_payment_date:
              paymentDate,
          }
        );

      if (cancelled) return;

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
          quote?.payment_amount ?? 0
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
          "ØªØ¹Ø°Ø± Ø­Ø³Ø§Ø¨ Ù…Ø¨Ù„Øº Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚."
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

    void refreshPaymentCurrencyQuote();

    return () => {
      cancelled = true;
    };
  }, [
    collection,
    paymentCashbox,
    paymentDate,
    paymentAmount,
    cashboxes,
    companyId,
    currency,
    supabase,
  ]);

  const highlighted =
    searchParams.get("order");

  const invoicesByOrder =
    useMemo(() => {
      const map =
        new Map<
          string,
          OrderSalesInvoice[]
        >();

      for (const invoice of invoices) {
        const current =
          map.get(
            invoice.order_id
          ) ?? [];

        current.push(invoice);

        map.set(
          invoice.order_id,
          current
        );
      }

      return map;
    }, [invoices]);

const activeOrders =
    useMemo(
      () =>
        orders.filter(
          (order) =>
            order.status !==
            "cancelled"
        ),
      [orders]
    );

  const sales =
    activeOrders.reduce(
      (sum, order) =>
        sum +
        Number(
          order.total || 0
        ),
      0
    );

  const orderTotal =
    useMemo(
      () =>
        items.reduce(
          (sum, item) =>
            sum +
            Number(
              item.quantity || 0
            ) *
              Number(
                item.sale_unit_price ||
                  0
              ),
          0
        ),
      [items]
    );

  function resetForm() {
    setTrader("");
    setItems([
      emptyItem(),
    ]);
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

  function chooseProduct(
    index: number,
    productId: string
  ) {
    const product =
      products.find(
        (row) =>
          row.id === productId
      );

    setItems((current) =>
      current.map(
        (item, currentIndex) =>
          currentIndex === index
            ? {
                ...item,

                product_id:
                  productId,

                sale_unit_price:
                  product?.sale_price !=
                  null
                    ? String(
                        product.sale_price
                      )
                    : "",
              }
            : item
      )
    );
  }

  function updateItem(
    index: number,
    changes: Partial<ItemDraft>
  ) {
    setItems((current) =>
      current.map(
        (item, currentIndex) =>
          currentIndex === index
            ? {
                ...item,
                ...changes,
              }
            : item
      )
    );
  }

  async function createOrder(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();
    setMessage("");

    if (!canCreate) {
      setMessage(
        "Ù…Ø§ Ø¹Ù†Ø¯Ùƒ ØµÙ„Ø§Ø­ÙŠØ© Ø¥Ù†Ø´Ø§Ø¡ Ø·Ù„Ø¨ÙŠØ©."
      );
      return;
    }

    if (!trader) {
      setMessage(
        "Ø§Ø®ØªØ§Ø± Ø§Ù„Ø²Ø¨ÙˆÙ†."
      );
      return;
    }

    if (
      !items.length ||
      items.some((item) => {
        const quantity =
          Number(
            item.quantity
          );

        const salePrice =
          Number(
            item.sale_unit_price
          );

        return (
          !item.product_id ||
          !Number.isFinite(
            quantity
          ) ||
          quantity <= 0 ||
          !Number.isFinite(
            salePrice
          ) ||
          salePrice < 0
        );
      })
    ) {
      setMessage(
        "Ø±Ø§Ø¬Ø¹ Ø§Ù„Ø£ØµÙ†Ø§Ù ÙˆØ§Ù„ÙƒÙ…ÙŠØ§Øª ÙˆØ£Ø³Ø¹Ø§Ø± Ø§Ù„Ø¨ÙŠØ¹."
      );
      return;
    }

    const payload =
      items.map((item) => ({
        product_id:
          item.product_id,

        quantity:
          Number(
            item.quantity
          ),

        sale_unit_price:
          Number(
            item.sale_unit_price
          ),
      }));

    setSaving(true);

    const { data, error } =
      await supabase.rpc(
        "create_sales_order_v2",
        {
          target_company:
            companyId,

          target_trader:
            trader,

          target_notes:
            notes.trim() ||
            null,

          items_payload:
            payload,

          target_source_quote:
            null,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    const result = data as
      | {
          status?: string;
          order_id?: string | null;
          approval_id?: string | null;
        }
      | null;

    if (
      result?.status ===
      "pending_approval"
    ) {
      setOpen(false);
      resetForm();
      window.alert(
        "Ø§Ù„Ø³Ø¹Ø± ØªØ­Øª Ø§Ù„ØªÙƒÙ„ÙØ© Ø£Ùˆ Ø§Ù„Ø­Ø¯ Ø§Ù„Ø£Ø¯Ù†Ù‰. ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø·Ù„Ø¨ Ù…ÙˆØ§ÙÙ‚Ø© ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹."
      );
      router.refresh();
      return;
    }

    setOpen(false);
    resetForm();

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }

  async function cancelOrder(
    id: string
  ) {
    if (!canCancel) {
      return;
    }

    const reason =
      window.prompt(
        "Ø³Ø¨Ø¨ Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ø·Ù„Ø¨ÙŠØ©:"
      );

    if (reason === null) {
      return;
    }

    if (!reason.trim()) {
      window.alert(
        "Ø§ÙƒØªØ¨ Ø³Ø¨Ø¨ Ø§Ù„Ø¥Ù„ØºØ§Ø¡."
      );
      return;
    }

    const confirmed =
      window.confirm(
        "ØªØ£ÙƒÙŠØ¯ Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ø·Ù„Ø¨ÙŠØ©ØŸ"
      );

    if (!confirmed) {
      return;
    }

    const { error } =
      await supabase.rpc(
        "cancel_sales_order",
        {
          target_company:
            companyId,

          target_order:
            id,

          target_reason:
            reason.trim(),
        }
      );

    if (error) {
      window.alert(
        error.message
      );
      return;
    }

    setOrders((current) =>
      current.map((order) =>
        order.id === id
          ? {
              ...order,
              status:
                "cancelled",
            }
          : order
      )
    );

    router.refresh();
  }

  function openCollection(
    order: OrderRow
  ) {
    if (!canCollect) {
      return;
    }

    if (
      order.status !==
      "delivered"
    ) {
      return;
    }

    const orderInvoices =
      (
        invoicesByOrder.get(
          order.id
        ) ?? []
      )
        .filter(
          (invoice) =>
            invoice.status ===
              "posted" &&
            Number(
              invoice.balance_due ||
                0
            ) > 0
        );

    if (!orderInvoices.length) {
      window.alert(
        "Ù…Ø§ ÙÙŠ ÙØ§ØªÙˆØ±Ø© Ù…Ø³ØªØ­Ù‚Ø© Ù„Ù‡Ø§Ù„Ø·Ù„Ø¨ÙŠØ©."
      );
      return;
    }

    const invoiceCurrency =
      orderInvoices[0]
        ?.currency ?? currency;

    if (
      orderInvoices.some(
        (invoice) =>
          invoice.currency !==
          invoiceCurrency
      )
    ) {
      window.alert(
        "ÙÙˆØ§ØªÙŠØ± Ø§Ù„Ø·Ù„Ø¨ÙŠØ© ÙÙŠÙ‡Ø§ Ø£ÙƒØ«Ø± Ù…Ù† Ø¹Ù…Ù„Ø© ÙˆÙ„Ø§ ÙŠÙ…ÙƒÙ† Ù‚Ø¨Ø¶Ù‡Ø§ Ø¨Ø¹Ù…Ù„ÙŠØ© ÙˆØ§Ø­Ø¯Ø©."
      );
      return;
    }

    const balance =
      orderInvoices.reduce(
        (sum, invoice) =>
          sum +
          Number(
            invoice.balance_due ||
              0
          ),
        0
      );

    const matchingCashbox =
      cashboxes.find(
        (cashbox) =>
          cashbox.currency ===
          invoiceCurrency
      );

    setCollection({
      order,
      invoices:
        orderInvoices,
    });

    setPaymentAmount(
      balance.toFixed(2)
    );

    setPaymentDate(
      localDateInput()
    );

    setPaymentMethod(
      "cash"
    );

    setPaymentCashbox(
      matchingCashbox?.id ??
        cashboxes[0]?.id ??
        ""
    );

    setPaymentCashAmount(
      balance.toFixed(2)
    );

    setPaymentCashCurrency(
      matchingCashbox
        ?.currency ??
        cashboxes[0]
          ?.currency ??
        invoiceCurrency
    );

    setPaymentInvoiceCurrency(
      invoiceCurrency
    );

    setPaymentFxRate(
      matchingCashbox
        ?.currency ===
        invoiceCurrency
        ? 1
        : null
    );

    setPaymentQuoteError("");
    setPaymentReference("");
    setPaymentNotes("");
    setPaymentMessage("");
  }

  async function saveCollection(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!collection) {
      return;
    }

    setPaymentMessage("");

    const amount =
      Number(
        paymentAmount
      );

    const balance =
      collection.invoices.reduce(
        (sum, invoice) =>
          sum +
          Number(
            invoice.balance_due ||
              0
          ),
        0
      );

    if (
      !Number.isFinite(
        amount
      ) ||
      amount <= 0
    ) {
      setPaymentMessage(
        "Ø§ÙƒØªØ¨ Ù…Ø¨Ù„Øº Ù‚Ø¨Ø¶ ØµØ­ÙŠØ­."
      );
      return;
    }

    if (
      amount >
      balance + 0.01
    ) {
      setPaymentMessage(
        `Ø§Ù„Ù…Ø¨Ù„Øº Ø£ÙƒØ¨Ø± Ù…Ù† Ø§Ù„Ø±ØµÙŠØ¯ Ø§Ù„Ù…Ø³ØªØ­Ù‚ ${balance.toFixed(
          2
        )} ${paymentInvoiceCurrency}.`
      );
      return;
    }

    if (!paymentCashbox) {
      setPaymentMessage(
        "Ø§Ø®ØªØ§Ø± Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚."
      );
      return;
    }

    if (!paymentDate) {
      setPaymentMessage(
        "Ø§Ø®ØªØ§Ø± ØªØ§Ø±ÙŠØ® Ø§Ù„Ù‚Ø¨Ø¶."
      );
      return;
    }

    const invoiceCurrency =
      collection.invoices[0]
        ?.currency ?? currency;

    const selectedCashbox =
      cashboxes.find(
        (cashbox) =>
          cashbox.id ===
          paymentCashbox
      );

    if (!selectedCashbox) {
      setPaymentMessage(
        "Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ Ø§Ù„Ù…Ø®ØªØ§Ø± ØºÙŠØ± ØµØ§Ù„Ø­."
      );
      return;
    }

    if (paymentQuoteError) {
      setPaymentMessage(
        paymentQuoteError
      );
      return;
    }

    const cashAmount =
      selectedCashbox.currency ===
      invoiceCurrency
        ? amount
        : Number(
            paymentCashAmount
          );

    if (
      !Number.isFinite(
        cashAmount
      ) ||
      cashAmount <= 0
    ) {
      setPaymentMessage(
        "ØªØ¹Ø°Ø± Ø­Ø³Ø§Ø¨ Ø§Ù„Ù…Ø¨Ù„Øº Ø¨Ø¹Ù…Ù„Ø© Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚."
      );
      return;
    }

    let remaining =
      Number(
        amount.toFixed(2)
      );

    const allocationsPayload:
      Array<{
        sales_invoice_id: string;
        amount: number;
      }> = [];

    for (
      const invoice of
      collection.invoices
    ) {
      if (
        remaining <= 0
      ) {
        break;
      }

      const invoiceBalance =
        Number(
          invoice.balance_due ||
            0
        );

      if (
        invoiceBalance <= 0
      ) {
        continue;
      }

      const applied =
        Math.min(
          remaining,
          invoiceBalance
        );

      allocationsPayload.push({
        sales_invoice_id:
          invoice.id,

        amount:
          Number(
            applied.toFixed(2)
          ),
      });

      remaining =
        Number(
          (
            remaining -
            applied
          ).toFixed(2)
        );
    }

    if (
      !allocationsPayload.length
    ) {
      setPaymentMessage(
        "Ù…Ø§ ÙÙŠ Ø±ØµÙŠØ¯ Ù…Ø³ØªØ­Ù‚ Ù„Ù„Ù‚Ø¨Ø¶."
      );
      return;
    }

    setCollecting(true);

    const { error } =
      await supabase.rpc(
        "record_customer_payment",
        {
          target_company:
            companyId,

          target_trader:
            collection.order
              .trader_id,

          target_cashbox:
            paymentCashbox,

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
            allocationsPayload,
        }
      );

    setCollecting(false);

    if (error) {
      setPaymentMessage(
        error.message
      );
      return;
    }

    setCollection(null);
    setPaymentAmount("");
    setPaymentCashAmount("");
    setPaymentQuoteError("");

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }

  const collectionTotal =
    collection
      ? collection.invoices.reduce(
          (sum, invoice) =>
            sum +
            Number(
              invoice.total || 0
            ),
          0
        )
      : 0;

  const collectionPaid =
    collection
      ? collection.invoices.reduce(
          (sum, invoice) =>
            sum +
            Number(
              invoice.paid_total ||
                0
            ),
          0
        )
      : 0;

  const collectionBalance =
    collection
      ? collection.invoices.reduce(
          (sum, invoice) =>
            sum +
            Number(
              invoice.balance_due ||
                0
            ),
          0
        )
      : 0;
  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª
          </span>

          <h2>
            Ø·Ù„Ø¨ÙŠØ§Øª Ø§Ù„Ø²Ø¨Ø§Ø¦Ù†
          </h2>

          <p className="muted">
            Ø·Ù„Ø¨ Ø§Ù„Ø¨ÙŠØ¹ ÙŠØ­ØªÙˆÙŠ Ø¹Ù„Ù‰
            Ø§Ù„Ø²Ø¨ÙˆÙ† ÙˆØ§Ù„Ø£ØµÙ†Ø§Ù ÙˆØ§Ù„ÙƒÙ…ÙŠØ§Øª
            ÙˆØ£Ø³Ø¹Ø§Ø± Ø§Ù„Ø¨ÙŠØ¹ ÙÙ‚Ø·.
          </p>
        </div>

        {canCreate && (
          <button
            type="button"
            className="primaryButton"
            onClick={startAdd}
          >
            <Icons.plus size={15} />
            Ø·Ù„Ø¨ÙŠØ© Ø¬Ø¯ÙŠØ¯Ø©
          </button>
        )}
      </div>

      <section className="statsGrid">
        <Mini
          title="Ø§Ù„Ø·Ù„Ø¨Ø§Øª Ø§Ù„ÙØ¹Ø§Ù„Ø©"
          value={String(
            activeOrders.length
          )}
        />

        <Mini
          title="Ø§Ù„Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø©"
          value={String(
            activeOrders.filter(
              (order) =>
                order.status ===
                "new"
            ).length
          )}
        />

        <Mini
          title="Ø¬Ø§Ù‡Ø²Ø© Ù„Ù„ØªÙˆØµÙŠÙ„"
          value={String(
            activeOrders.filter(
              (order) =>
                [
                  "ready",
                  "out_for_delivery",
                ].includes(
                  order.status
                )
            ).length
          )}
        />

        <Mini
          title="Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø·Ù„Ø¨Ø§Øª"
          value={`${sales.toFixed(
            2
          )} ${currency}`}
        />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        {!orders.length ? (
          <div className="empty">
            <Icons.cart size={29} />

            <h3>
              Ù…Ø§ ÙÙŠ Ø·Ù„Ø¨ÙŠØ§Øª
            </h3>

            <p>
              Ø£Ø¶Ù Ø£ÙˆÙ„ Ø·Ù„Ø¨ÙŠØ© Ø²Ø¨ÙˆÙ†.
            </p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>Ø§Ù„Ø·Ù„Ø¨</th>
                  <th>Ø§Ù„Ø²Ø¨ÙˆÙ†</th>
                  <th>Ø§Ù„Ø£ØµÙ†Ø§Ù</th>
                  <th>Ø§Ù„Ø­Ø§Ù„Ø©</th>
                  <th>Ø§Ù„Ø¥Ø¬Ù…Ø§Ù„ÙŠ</th>
                  <th>Ø§Ù„Ø¯ÙØ¹</th>
                  <th>Ø§Ù„ÙØ§ØªÙˆØ±Ø©</th>
                  <th>Ø¥Ø¬Ø±Ø§Ø¡Ø§Øª</th>
                </tr>
              </thead>

              <tbody>
                {orders.map(
                  (order) => {
                    const traderRow =
                      oneRelation(
                        order.traders
                      );

                    const orderInvoices =
                      invoicesByOrder.get(
                        order.id
                      ) ?? [];

                    const dueInvoices =
                      orderInvoices.filter(
                        (row) =>
                          Number(
                            row.balance_due ||
                              0
                          ) > 0
                      );

                    const outstandingBalance =
                      dueInvoices.reduce(
                        (sum, row) =>
                          sum +
                          Number(
                            row.balance_due ||
                              0
                          ),
                        0
                      );

                    const firstInvoice =
                      dueInvoices[0] ??
                      orderInvoices[0];

                    const invoice =
                      firstInvoice
                        ? {
                            ...firstInvoice,
                            invoice_number:
                              orderInvoices.length >
                              1
                                ? `${orderInvoices.length} \u0641\u0648\u0627\u062a\u064a\u0631`
                                : firstInvoice.invoice_number,

                            balance_due:
                              outstandingBalance,
                          }
                        : undefined;

                    const paymentStatus =
                      order.payment_status;

                    return (
                      <tr
                        key={order.id}
                        style={
                          highlighted ===
                          order.id
                            ? {
                                background:
                                  "rgba(42,201,156,.045)",
                              }
                            : undefined
                        }
                      >
                        <td>
                          <strong>
                            #
                            {order.id.slice(
                              0,
                              8
                            )}
                          </strong>

                          <div className="muted">
                            {new Date(
                              order.created_at
                            ).toLocaleString(
                              "ar-LB"
                            )}
                          </div>
                        </td>

                        <td>
                          <strong>
                            {traderRow?.name ||
                              "â€”"}
                          </strong>

                          {traderRow?.area && (
                            <div className="muted">
                              {
                                traderRow.area
                              }
                            </div>
                          )}
                        </td>

                        <td>
                          <strong>
                            {
                              order
                                .sales_order_items
                                .length
                            }
                          </strong>

                          <div className="muted">
                            {order.sales_order_items
                              .slice(0, 2)
                              .map((item) => {
                                const product =
                                  oneRelation(
                                    item.products
                                  );

                                return (
                                  product?.name ??
                                  "ØµÙ†Ù"
                                );
                              })
                              .join("ØŒ ")}

                            {order
                              .sales_order_items
                              .length >
                              2 &&
                              " ..."}
                          </div>
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              [
                                "ready",
                                "delivered",
                              ].includes(
                                order.status
                              )
                                ? "green"
                                : order.status ===
                                    "cancelled"
                                  ? "gray"
                                  : "orange"
                            }`}
                          >
                            {
                              statusLabels[
                                order.status
                              ]
                            }
                          </span>
                        </td>

                        <td>
                          {Number(
                            order.total ||
                              0
                          ).toFixed(2)}{" "}
                          {currency}
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              paymentStatus ===
                              "paid"
                                ? "green"
                                : paymentStatus ===
                                    "partial"
                                  ? "orange"
                                  : "gray"
                            }`}
                          >
                            {paymentLabel(
                              paymentStatus
                            )}
                          </span>
                        </td>

                        <td>
                          {invoice ? (
                            <div>
                              <strong>
                                {
                                  invoice.invoice_number
                                }
                              </strong>

                              <div className="muted">
                                Ù…ØªØ¨Ù‚ÙŠ{" "}
                                {Number(
                                  invoice.balance_due
                                ).toFixed(
                                  2
                                )}{" "}
                                {currency}
                              </div>
                            </div>
                          ) : (
                            <span className="muted">
                              â€”
                            </span>
                          )}
                        </td>

                        <td>
                          <div className="rowActions">
                            {[
                              "ready",
                              "out_for_delivery",
                            ].includes(
                              order.status
                            ) && (
                              <a
                                className="softButton"
                                href="/deliveries"
                              >
                                ØªÙˆØµÙŠÙ„
                              </a>
                            )}

                            {canCollect &&
                              invoice &&
                              Number(
                                invoice.balance_due
                              ) > 0 && (
                                <button
                                  type="button"
                                  className="primaryButton"
                                  onClick={() =>
                                    openCollection(
                                      order
                                    )
                                  }
                                >
                                  Ù‚Ø¨Ø¶
                                </button>
                              )}

                            {canCancel &&
                              ![
                                "delivered",
                                "cancelled",
                              ].includes(
                                order.status
                              ) && (
                                <button
                                  type="button"
                                  className="dangerButton"
                                  onClick={() =>
                                    void cancelOrder(
                                      order.id
                                    )
                                  }
                                >
                                  Ø¥Ù„ØºØ§Ø¡
                                </button>
                              )}
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

      {open && (
        <div className="modalOverlay">
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
                  Ø§Ù„Ù…Ø¨ÙŠØ¹Ø§Øª
                </span>

                <h2>
                  Ø·Ù„Ø¨ÙŠØ© Ø²Ø¨ÙˆÙ† Ø¬Ø¯ÙŠØ¯Ø©
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() =>
                  setOpen(false)
                }
              >
                Ã—
              </button>
            </div>

            <form
              onSubmit={createOrder}
            >
              <label className="field">
                <span>
                  Ø§Ù„Ø²Ø¨ÙˆÙ† *
                </span>

                <select
                  value={trader}
                  onChange={(event) =>
                    setTrader(
                      event.target
                        .value
                    )
                  }
                >
                  <option value="">
                    Ø§Ø®ØªØ± Ø§Ù„Ø²Ø¨ÙˆÙ†
                  </option>

                  {traders.map(
                    (row) => (
                      <option
                        key={row.id}
                        value={row.id}
                      >
                        {row.name}
                        {row.area
                          ? ` - ${row.area}`
                          : ""}
                      </option>
                    )
                  )}
                </select>
              </label>

              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                <div className="panelHeader">
                  <div>
                    <h2>
                      Ø§Ù„Ø£ØµÙ†Ø§Ù
                    </h2>

                    <p>
                      Ø§Ù„Ù…ÙˆØ±Ø¯ ÙˆØ³Ø¹Ø± Ø§Ù„Ø´Ø±Ø§Ø¡
                      Ù„ÙŠØ³Ø§ Ø¬Ø²Ø¡Ù‹Ø§ Ù…Ù† Ø·Ù„Ø¨
                      Ø§Ù„Ø²Ø¨ÙˆÙ†.
                    </p>
                  </div>

                  <button
                    type="button"
                    className="softButton"
                    onClick={() =>
                      setItems(
                        (
                          current
                        ) => [
                          ...current,
                          emptyItem(),
                        ]
                      )
                    }
                  >
                    <Icons.plus
                      size={13}
                    />
                    ØµÙ†Ù
                  </button>
                </div>

                <div className="quickList">
                  {items.map(
                    (
                      item,
                      index
                    ) => (
                      <div
                        key={
                          item.key
                        }
                        className="quickItem"
                        style={{
                          display:
                            "grid",
                          gridTemplateColumns:
                            "2fr .8fr 1fr auto",
                          alignItems:
                            "end",
                        }}
                      >
                        <label className="field">
                          <span>
                            Ø§Ù„ØµÙ†Ù
                          </span>

                          <select
                            value={
                              item.product_id
                            }
                            onChange={(
                              event
                            ) =>
                              chooseProduct(
                                index,
                                event
                                  .target
                                  .value
                              )
                            }
                          >
                            <option value="">
                              Ø§Ø®ØªØ±
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
                                  {product.sku
                                    ? ` - ${product.sku}`
                                    : ""}
                                </option>
                              )
                            )}
                          </select>
                        </label>

                        <label className="field">
                          <span>
                            Ø§Ù„ÙƒÙ…ÙŠØ©
                          </span>

                          <input
                            type="number"
                            min="0.001"
                            step="0.001"
                            value={
                              item.quantity
                            }
                            onChange={(
                              event
                            ) =>
                              updateItem(
                                index,
                                {
                                  quantity:
                                    event
                                      .target
                                      .value,
                                }
                              )
                            }
                          />
                        </label>

                        <label className="field">
                          <span>
                            Ø³Ø¹Ø± Ø§Ù„Ø¨ÙŠØ¹
                          </span>

                          <input
                            type="number"
                            min="0"
                            step="0.01"
                            value={
                              item.sale_unit_price
                            }
                            onChange={(
                              event
                            ) =>
                              updateItem(
                                index,
                                {
                                  sale_unit_price:
                                    event
                                      .target
                                      .value,
                                }
                              )
                            }
                          />
                        </label>

                        <button
                          type="button"
                          className="dangerButton"
                          disabled={
                            items.length ===
                            1
                          }
                          onClick={() =>
                            setItems(
                              (
                                current
                              ) =>
                                current.filter(
                                  (
                                    _,
                                    rowIndex
                                  ) =>
                                    rowIndex !==
                                    index
                                )
                            )
                          }
                        >
                          Ã—
                        </button>
                      </div>
                    )
                  )}
                </div>
              </div>

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>
                  Ù…Ù„Ø§Ø­Ø¸Ø§Øª
                </span>

                <textarea
                  rows={3}
                  value={notes}
                  onChange={(event) =>
                    setNotes(
                      event.target
                        .value
                    )
                  }
                />
              </label>

              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                <div className="panelHeader">
                  <strong>
                    Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø·Ù„Ø¨ÙŠØ©
                  </strong>

                  <div className="statValue">
                    {orderTotal.toFixed(
                      2
                    )}{" "}
                    {currency}
                  </div>
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

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() =>
                    setOpen(false)
                  }
                >
                  Ø¥Ù„ØºØ§Ø¡
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving
                    ? "Ø¹Ù… Ù†Ø­ÙØ¸..."
                    : "Ø­ÙØ¸ Ø§Ù„Ø·Ù„Ø¨ÙŠØ©"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {collection && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 680,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Ø§Ù„ØªØ­ØµÙŠÙ„
                </span>

                <h2>
                  Ù‚Ø¨Ø¶ Ù…Ù† Ø§Ù„Ø²Ø¨ÙˆÙ†
                </h2>

                <p className="muted">
                  ÙØ§ØªÙˆØ±Ø©{" "}
                  {
                    collection.invoices.length === 1 ? collection.invoices[0].invoice_number : `${collection.invoices.length} \u0641\u0648\u0627\u062a\u064a\u0631`
                  }
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={collecting}
                onClick={() =>
                  setCollection(null)
                }
              >
                Ã—
              </button>
            </div>

            <section className="statsGrid">
              <Mini
                title="Ø§Ù„ÙØ§ØªÙˆØ±Ø©"
                value={`${collectionTotal.toFixed(2)} ${currency}`}
              />

              <Mini
                title="Ù…Ù‚Ø¨ÙˆØ¶"
                value={`${collectionPaid.toFixed(2)} ${currency}`}
              />

              <Mini
                title="Ø§Ù„Ù…ØªØ¨Ù‚ÙŠ"
                value={`${collectionBalance.toFixed(2)} ${currency}`}
              />
            </section>

            <form
              onSubmit={
                saveCollection
              }
            >
              <div
                className="formGrid"
                style={{
                  marginTop: 16,
                }}
              >
                <label className="field">
                  <span>
                    Ø§Ù„Ù…Ø¨Ù„Øº *
                  </span>

                  <input
                    type="number"
                    min="0.01"
                    step="0.01"
                    max={collectionBalance}
                    value={
                      paymentAmount
                    }
                    onChange={(event) =>
                      setPaymentAmount(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    Ø§Ù„ØªØ§Ø±ÙŠØ® *
                  </span>

                  <input
                    type="date"
                    value={
                      paymentDate
                    }
                    onChange={(event) =>
                      setPaymentDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    Ø§Ù„ØµÙ†Ø¯ÙˆÙ‚ *
                  </span>

                  <select
                    value={
                      paymentCashbox
                    }
                    onChange={(event) =>
                      setPaymentCashbox(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="">
                      Ø§Ø®ØªØ±
                    </option>

                    {cashboxes.map(
                      (cashbox) => (
                        <option
                          key={
                            cashbox.id
                          }
                          value={
                            cashbox.id
                          }
                        >
                          {
                            cashbox.name
                          }{" "}
                          -{" "}
                          {
                            cashbox.currency
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    Ø·Ø±ÙŠÙ‚Ø© Ø§Ù„Ø¯ÙØ¹ *
                  </span>

                  <select
                    value={
                      paymentMethod
                    }
                    onChange={(event) =>
                      setPaymentMethod(
                        event.target
                          .value as PaymentMethod
                      )
                    }
                  >
                    <option value="cash">
                      Ù†Ù‚Ø¯ÙŠ
                    </option>
                    <option value="bank">
                      ØªØ­ÙˆÙŠÙ„ Ø¨Ù†ÙƒÙŠ
                    </option>
                    <option value="card">
                      Ø¨Ø·Ø§Ù‚Ø©
                    </option>
                    <option value="check">
                      Ø´ÙŠÙƒ
                    </option>
                    <option value="other">
                      Ø£Ø®Ø±Ù‰
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>
                    Ø§Ù„Ù…Ø±Ø¬Ø¹
                  </span>

                  <input
                    value={
                      paymentReference
                    }
                    onChange={(event) =>
                      setPaymentReference(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    Ù…Ù„Ø§Ø­Ø¸Ø§Øª
                  </span>

                  <textarea
                    rows={3}
                    value={
                      paymentNotes
                    }
                    onChange={(event) =>
                      setPaymentNotes(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

                            {paymentCashbox &&
              Number(
                paymentAmount || 0
              ) > 0 ? (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {paymentQuoteError ? (
                    <div className="toastError">
                      {paymentQuoteError}
                    </div>
                  ) : (
                    <>
                      <div className="muted">
                        ØªØ³Ø¯ÙŠØ¯ Ø§Ù„ÙÙˆØ§ØªÙŠØ±:{" "}
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
                        Ø³ÙŠØªÙ… Ù‚Ø¨Ø¶:{" "}
                        {paymentCashAmount ||
                          "â€”"}{" "}
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
                          Ø³Ø¹Ø± Ø§Ù„Ø¹Ù…Ù„ÙŠØ©: 1{" "}
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
{paymentMessage && (
                <div
                  className="toastError"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {paymentMessage}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={
                    collecting
                  }
                  onClick={() =>
                    setCollection(null)
                  }
                >
                  Ø¥Ù„ØºØ§Ø¡
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    collecting
                  }
                >
                  {collecting
                    ? "Ø¹Ù… Ù†Ø³Ø¬Ù„..."
                    : "ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ù‚Ø¨Ø¶"}
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
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

