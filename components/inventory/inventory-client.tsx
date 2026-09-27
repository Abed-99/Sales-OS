"use client";

import { useMemo, useState } from "react";
import type { FormEvent } from "react";
import { useRouter, useSearchParams } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type InventoryWarehouse = {
  id: string;
  code: string | null;
  name: string;
  address: string | null;
  is_default: boolean;
  active: boolean;
};

export type InventoryProduct = {
  id: string;
  name: string;
  sku: string | null;
  unit: string | null;
  active: boolean;
};

export type InventoryStockRow = {
  company_id: string;
  warehouse_id: string;
  warehouse_name: string;
  product_id: string;
  sku: string | null;
  product_name: string;
  unit: string | null;
  on_hand: number;
  reserved: number;
  available: number;
  average_cost: number | null;
  stock_value: number | null;
  updated_at: string;
};

export type InventoryReceivableItem = {
  invoice_id: string;
  supplier_id: string;
  invoice_number: string;
  supplier_invoice_number: string | null;
  currency: string;
  invoice_date: string;
  invoice_total: number;
  supplier_name: string;
  item_id: string;
  product_id: string;
  description: string | null;
  invoiced_quantity: number;
  received_quantity: number;
  remaining_quantity: number;
  product_name: string;
  sku: string | null;
  unit: string | null;
};

export type InventoryReceiptRow = {
  id: string;
  receipt_number: string;
  warehouse_id: string;
  purchase_invoice_id: string | null;
  status: string;
  receipt_date: string;
  notes: string | null;
  cancellation_reason: string | null;
  created_at: string;
};

export type InventoryTransferRow = {
  id: string;
  transfer_number: string;
  source_warehouse_id: string;
  destination_warehouse_id: string;
  status: string;
  transfer_date: string;
  notes: string | null;
  reversal_reason: string | null;
  created_at: string;
};

export type InventoryCountRow = {
  id: string;
  warehouse_id: string;
  count_number: string;
  count_date: string;
  status: string;
  notes: string | null;
  reversal_reason: string | null;
  created_at: string;
};

type InventoryStats = {
  warehouseCount: number;
  reservedLines: number;
  outOfStock: number;
  stockValue: number;
  pendingReceiptInvoices: number;
};

type ReceivableInvoice = {
  id: string;
  supplier_id: string;
  invoice_number: string;
  supplier_invoice_number: string | null;
  currency: string;
  invoice_date: string;
  invoice_total: number;
  supplier_name: string;
  items: InventoryReceivableItem[];
};

type TransferDraft = {
  key: string;
  productId: string;
  quantity: string;
};

type CountDraft = {
  productId: string;
  productName: string;
  sku: string | null;
  systemQuantity: number;
  countedQuantity: string;
  unitCost: string;
};

type ReverseKind = "receipt" | "transfer" | "count";

type ReverseTarget = {
  kind: ReverseKind;
  id: string;
  number: string;
};

type Notice = {
  type: "success" | "error";
  text: string;
};

function numeric(value: unknown) {
  const result = Number(value ?? 0);

  return Number.isFinite(result) ? result : 0;
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

function newKey() {
  return crypto.randomUUID();
}

/** 100 بدل 100.000، و 2.5 بدل 2.500 */
function qty(value: unknown) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 3 }).format(numeric(value));
}

function money(value: number, currency: string) {
  return `${new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(numeric(value))} ${currency}`;
}

function statusLabel(status: string) {
  if (status === "posted") {
    return "مرحّل";
  }

  if (status === "reversed") {
    return "معكوس";
  }

  if (status === "cancelled") {
    return "ملغى";
  }

  return status;
}

function friendlyError(
  error: {
    code?: string;
    message?: string;
  } | null,
  action: "receive" | "warehouse" | "transfer" | "count" | "reverse",
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

  if (message.includes("invalid warehouse")) {
    return "المستودع المختار غير صالح أو غير فعال.";
  }

  if (message.includes("invalid product")) {
    return "أحد الأصناف غير صالح.";
  }

  if (message.includes("receipt exceeds purchased quantity")) {
    return "الكمية المستلمة أكبر من الكمية المتبقية في فاتورة الشراء.";
  }

  if (message.includes("purchase invoice is not posted")) {
    return "فاتورة الشراء لم تعد متاحة للاستلام.";
  }

  if (message.includes("transfer exceeds available stock")) {
    return "الكمية المطلوبة للتحويل أكبر من المخزون المتاح بعد الحجوزات.";
  }

  if (message.includes("duplicate transfer product")) {
    return "لا يمكن تكرار نفس الصنف في التحويل.";
  }

  if (message.includes("counted quantity is below reserved stock")) {
    return "نتيجة الجرد أقل من الكمية المحجوزة ولا يمكن ترحيلها.";
  }

  if (message.includes("unit cost is required")) {
    return "هذا الصنف لا يملك كلفة مخزون سابقة أو سعر شراء مرجعي. يلزم إدخال كلفة صحيحة بواسطة مستخدم مخوّل.";
  }

  if (message.includes("not allowed to set inventory cost")) {
    return "لا تملك صلاحية إدخال كلفة لمخزون جديد.";
  }

  if (message.includes("inventory value would become negative")) {
    return "تعذر عكس الحركة لأن قيمة المخزون الناتجة ستصبح غير صحيحة.";
  }

  if (message.includes("cannot reverse receipt")) {
    return "لا يمكن عكس الاستلام لأن جزءاً من البضاعة تم حجزه أو نقله أو استخدامه.";
  }

  if (message.includes("cannot reverse transfer")) {
    return "لا يمكن عكس التحويل لأن مخزون مستودع الوجهة تم حجزه أو استخدامه.";
  }

  if (message.includes("cannot reverse stock count")) {
    return "لا يمكن عكس الجرد لأن جزءاً من الكمية المعدلة تم حجزه أو استخدامه.";
  }

  if (message.includes("reversal reason")) {
    return "سبب العكس مطلوب.";
  }

  if (action === "receive") {
    return "تعذر تسجيل استلام البضاعة. راجع البيانات وحاول مرة ثانية.";
  }

  if (action === "warehouse") {
    return "تعذر حفظ بيانات المستودع.";
  }

  if (action === "transfer") {
    return "تعذر ترحيل تحويل المخزون.";
  }

  if (action === "count") {
    return "تعذر ترحيل الجرد.";
  }

  return "تعذر عكس حركة المخزون.";
}

export function InventoryClient({
  companyId,
  currency,
  warehouses,
  stock,
  stockTotalCount,
  stockPage,
  pageSize,
  searchQuery,
  warehouseFilter,
  stockStats,
  products,
  receivableItems,
  receipts,
  transfers,
  counts,
  initialError,
  canReceive,
  canReverseReceipt,
  canAdjust,
  canViewCost,
}: {
  companyId: string;
  currency: string;
  warehouses: InventoryWarehouse[];
  stock: InventoryStockRow[];
  stockTotalCount: number;
  stockPage: number;
  pageSize: number;
  searchQuery: string;
  warehouseFilter: string;
  stockStats: InventoryStats;
  products: InventoryProduct[];
  receivableItems: InventoryReceivableItem[];
  receipts: InventoryReceiptRow[];
  transfers: InventoryTransferRow[];
  counts: InventoryCountRow[];
  initialError: string | null;
  canReceive: boolean;
  canReverseReceipt: boolean;
  canAdjust: boolean;
  canViewCost: boolean;
}) {
  const [supabase] = useState(() => createClient());

  const router = useRouter();

  const searchParams = useSearchParams();

  const [notice, setNotice] = useState<Notice | null>(
    initialError
      ? {
          type: "error",
          text: initialError,
        }
      : null,
  );

  const [search, setSearch] = useState(searchQuery);

  const [warehouseSearch, setWarehouseSearch] = useState(warehouseFilter);

  const [saving, setSaving] = useState(false);

  // ==========================================================
  // WAREHOUSE
  // ==========================================================

  const [warehouseOpen, setWarehouseOpen] = useState(false);

  const [warehouseName, setWarehouseName] = useState("");

  const [warehouseCode, setWarehouseCode] = useState("");

  const [warehouseAddress, setWarehouseAddress] = useState("");

  const [warehouseDefault, setWarehouseDefault] = useState(false);

  const [warehouseMessage, setWarehouseMessage] = useState("");

  // ==========================================================
  // RECEIPT
  // ==========================================================

  const [selectedInvoice, setSelectedInvoice] = useState<ReceivableInvoice | null>(null);

  const [receiptWarehouse, setReceiptWarehouse] = useState("");

  const [receiptDate, setReceiptDate] = useState(businessDateInput());

  const [receiptNotes, setReceiptNotes] = useState("");

  const [receiptQuantities, setReceiptQuantities] = useState<Record<string, string>>({});

  const [receiptMessage, setReceiptMessage] = useState("");

  // ==========================================================
  // TRANSFER
  // ==========================================================

  const [transferOpen, setTransferOpen] = useState(false);

  const [transferSource, setTransferSource] = useState("");

  const [transferDestination, setTransferDestination] = useState("");

  const [transferDate, setTransferDate] = useState(businessDateInput());

  const [transferNotes, setTransferNotes] = useState("");

  const [transferLines, setTransferLines] = useState<TransferDraft[]>([]);

  const [transferMessage, setTransferMessage] = useState("");

  // ==========================================================
  // COUNT
  // ==========================================================

  const [countOpen, setCountOpen] = useState(false);

  const [countWarehouse, setCountWarehouse] = useState("");

  const [countDate, setCountDate] = useState(businessDateInput());

  const [countNotes, setCountNotes] = useState("");

  const [countLines, setCountLines] = useState<CountDraft[]>([]);

  const [countMessage, setCountMessage] = useState("");

  const [loadingCount, setLoadingCount] = useState(false);

  // ==========================================================
  // REVERSAL
  // ==========================================================

  const [reverseTarget, setReverseTarget] = useState<ReverseTarget | null>(null);

  const [reverseReason, setReverseReason] = useState("");

  const [reverseMessage, setReverseMessage] = useState("");

  const [reversing, setReversing] = useState(false);

  // ==========================================================
  // DERIVED DATA
  // ==========================================================

  const receivableInvoices = useMemo(() => {
    const map = new Map<string, ReceivableInvoice>();

    for (const item of receivableItems) {
      const existing = map.get(item.invoice_id);

      if (existing) {
        existing.items.push(item);

        continue;
      }

      map.set(item.invoice_id, {
        id: item.invoice_id,

        supplier_id: item.supplier_id,

        invoice_number: item.invoice_number,

        supplier_invoice_number: item.supplier_invoice_number,

        currency: item.currency,

        invoice_date: item.invoice_date,

        invoice_total: item.invoice_total,

        supplier_name: item.supplier_name,

        items: [item],
      });
    }

    return Array.from(map.values());
  }, [receivableItems]);

  const stockPageCount = Math.max(1, Math.ceil(stockTotalCount / pageSize));

  function warehouseNameById(id: string) {
    return warehouses.find((warehouse) => warehouse.id === id)?.name ?? "مستودع";
  }

  // ==========================================================
  // STOCK NAVIGATION
  // ==========================================================

  function navigateStock(nextSearch: string, nextWarehouse: string, nextPage = 1) {
    const params = new URLSearchParams(searchParams.toString());

    const clean = nextSearch.trim();

    if (clean) {
      params.set("q", clean);
    } else {
      params.delete("q");
    }

    if (nextWarehouse && nextWarehouse !== "all") {
      params.set("warehouse", nextWarehouse);
    } else {
      params.delete("warehouse");
    }

    if (nextPage > 1) {
      params.set("page", String(nextPage));
    } else {
      params.delete("page");
    }

    const query = params.toString();

    router.push(query ? `/inventory?${query}` : "/inventory");
  }

  // ==========================================================
  // WAREHOUSE ACTIONS
  // ==========================================================

  function openWarehouse() {
    if (!canAdjust) {
      return;
    }

    setWarehouseName("");
    setWarehouseCode("");
    setWarehouseAddress("");
    setWarehouseDefault(false);
    setWarehouseMessage("");
    setWarehouseOpen(true);
  }

  async function saveWarehouse(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!canAdjust) {
      return;
    }

    if (!warehouseName.trim()) {
      setWarehouseMessage("اسم المستودع مطلوب.");
      return;
    }

    setSaving(true);
    setWarehouseMessage("");

    try {
      const { error } = await supabase.rpc("create_warehouse", {
        target_company: companyId,

        target_name: warehouseName.trim(),

        target_code: warehouseCode.trim() || null,

        target_address: warehouseAddress.trim() || null,

        target_is_default: warehouseDefault,
      });

      if (error) {
        setWarehouseMessage(friendlyError(error, "warehouse"));
        return;
      }

      setWarehouseOpen(false);

      setNotice({
        type: "success",
        text: "تم إنشاء المستودع بنجاح.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  async function makeDefaultWarehouse(warehouseId: string) {
    if (!canAdjust) {
      return;
    }

    setSaving(true);

    try {
      const { error } = await supabase.rpc("set_default_warehouse", {
        target_company: companyId,

        target_warehouse: warehouseId,
      });

      if (error) {
        setNotice({
          type: "error",
          text: friendlyError(error, "warehouse"),
        });
        return;
      }

      setNotice({
        type: "success",
        text: "تم تغيير المستودع الرئيسي.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  // ==========================================================
  // GOODS RECEIPT
  // ==========================================================

  function openReceipt(invoice: ReceivableInvoice) {
    if (!canReceive) {
      return;
    }

    const defaultWarehouse = warehouses.find((warehouse) => warehouse.is_default) ?? warehouses[0];

    const quantities: Record<string, string> = {};

    for (const item of invoice.items) {
      quantities[item.item_id] = String(numeric(item.remaining_quantity));
    }

    setSelectedInvoice(invoice);

    setReceiptWarehouse(defaultWarehouse?.id ?? "");

    setReceiptDate(businessDateInput());

    setReceiptNotes("");

    setReceiptQuantities(quantities);

    setReceiptMessage("");
  }

  async function saveReceipt(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedInvoice || !canReceive) {
      return;
    }

    if (!receiptWarehouse) {
      setReceiptMessage("اختر المستودع.");
      return;
    }

    const items: Array<{
      purchase_invoice_item_id: string;
      quantity: number;
    }> = [];

    for (const item of selectedInvoice.items) {
      const quantity = numeric(receiptQuantities[item.item_id]);

      if (quantity < 0) {
        setReceiptMessage("كمية الاستلام لا يمكن أن تكون سالبة.");
        return;
      }

      if (quantity > numeric(item.remaining_quantity) + 0.0005) {
        setReceiptMessage(`كمية ${item.product_name} أكبر من الكمية المتبقية.`);
        return;
      }

      if (quantity > 0) {
        items.push({
          purchase_invoice_item_id: item.item_id,

          quantity: Number(quantity.toFixed(3)),
        });
      }
    }

    if (!items.length) {
      setReceiptMessage("حدد كمية مستلمة لصنف واحد على الأقل.");
      return;
    }

    setSaving(true);
    setReceiptMessage("");

    try {
      const { error } = await supabase.rpc("receive_purchase_invoice", {
        target_company: companyId,

        target_invoice: selectedInvoice.id,

        target_warehouse: receiptWarehouse,

        target_receipt_date: receiptDate,

        target_notes: receiptNotes.trim() || null,

        items_payload: items,
      });

      if (error) {
        setReceiptMessage(friendlyError(error, "receive"));
        return;
      }

      setSelectedInvoice(null);

      setNotice({
        type: "success",
        text: "تم استلام البضاعة وتحديث المخزون.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  // ==========================================================
  // TRANSFER
  // ==========================================================

  function openTransfer() {
    if (!canAdjust) {
      return;
    }

    const source = warehouses.find((warehouse) => warehouse.is_default) ?? warehouses[0];

    const destination = warehouses.find((warehouse) => warehouse.id !== source?.id);

    setTransferSource(source?.id ?? "");

    setTransferDestination(destination?.id ?? "");

    setTransferDate(businessDateInput());

    setTransferNotes("");

    setTransferLines([
      {
        key: newKey(),
        productId: "",
        quantity: "",
      },
    ]);

    setTransferMessage("");

    setTransferOpen(true);
  }

  function addTransferLine() {
    setTransferLines((current) => [
      ...current,
      {
        key: newKey(),
        productId: "",
        quantity: "",
      },
    ]);
  }

  async function saveTransfer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!canAdjust) {
      return;
    }

    if (!transferSource || !transferDestination) {
      setTransferMessage("اختر مستودع المصدر والوجهة.");
      return;
    }

    if (transferSource === transferDestination) {
      setTransferMessage("مستودع المصدر والوجهة يجب أن يكونا مختلفين.");
      return;
    }

    const selectedProducts = transferLines.map((line) => line.productId).filter(Boolean);

    if (new Set(selectedProducts).size !== selectedProducts.length) {
      setTransferMessage("لا يمكن تكرار نفس الصنف في التحويل.");
      return;
    }

    const items: Array<{
      product_id: string;
      quantity: number;
    }> = [];

    for (const line of transferLines) {
      const quantity = numeric(line.quantity);

      if (!line.productId || quantity <= 0) {
        setTransferMessage("راجع الأصناف والكميات في التحويل.");
        return;
      }

      items.push({
        product_id: line.productId,

        quantity: Number(quantity.toFixed(3)),
      });
    }

    if (!items.length) {
      setTransferMessage("أضف صنفاً واحداً على الأقل.");
      return;
    }

    setSaving(true);
    setTransferMessage("");

    try {
      const { error } = await supabase.rpc("post_inventory_transfer", {
        target_company: companyId,

        target_source_warehouse: transferSource,

        target_destination_warehouse: transferDestination,

        target_transfer_date: transferDate,

        target_notes: transferNotes.trim() || null,

        items_payload: items,
      });

      if (error) {
        setTransferMessage(friendlyError(error, "transfer"));
        return;
      }

      setTransferOpen(false);

      setNotice({
        type: "success",
        text: "تم ترحيل تحويل المخزون.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  // ==========================================================
  // PHYSICAL COUNT
  // ==========================================================

  async function loadCountWarehouse(warehouseId: string) {
    setCountWarehouse(warehouseId);

    setCountMessage("");

    if (!warehouseId) {
      setCountLines([]);
      return;
    }

    setLoadingCount(true);

    try {
      const { data, error } = await supabase
        .from("inventory_summary")
        .select("product_id,on_hand,average_cost")
        .eq("company_id", companyId)
        .eq("warehouse_id", warehouseId);

      if (error) {
        setCountMessage("تعذر تحميل رصيد المستودع للجرد.");
        return;
      }

      const current = new Map<
        string,
        {
          onHand: number;
          averageCost: number | null;
        }
      >();

      for (const row of data ?? []) {
        current.set(row.product_id, {
          onHand: numeric(row.on_hand),

          averageCost: row.average_cost == null ? null : numeric(row.average_cost),
        });
      }

      setCountLines(
        products.map((product) => {
          const balance = current.get(product.id);

          return {
            productId: product.id,

            productName: product.name,

            sku: product.sku,

            systemQuantity: numeric(balance?.onHand),

            countedQuantity: String(numeric(balance?.onHand)),

            unitCost:
              canViewCost && balance?.averageCost != null ? balance.averageCost.toFixed(4) : "",
          };
        }),
      );
    } finally {
      setLoadingCount(false);
    }
  }

  async function openCount() {
    if (!canAdjust) {
      return;
    }

    const warehouse = warehouses.find((row) => row.is_default) ?? warehouses[0];

    setCountDate(businessDateInput());

    setCountNotes("");

    setCountMessage("");

    setCountOpen(true);

    await loadCountWarehouse(warehouse?.id ?? "");
  }

  async function saveCount(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!canAdjust) {
      return;
    }

    if (!countWarehouse) {
      setCountMessage("اختر المستودع.");
      return;
    }

    if (!countLines.length) {
      setCountMessage("لا توجد أصناف للجرد.");
      return;
    }

    const items: Array<{
      product_id: string;
      counted_quantity: number;
      unit_cost: number | null;
    }> = [];

    for (const line of countLines) {
      const quantity = Number(line.countedQuantity);

      if (!Number.isFinite(quantity) || quantity < 0) {
        setCountMessage(`راجع كمية ${line.productName}.`);
        return;
      }

      // منبعت بس الأصناف اللي كميتها تغيّرت. هيك إذا انباعت بضاعة وانت عم تجرد،
      // ما منرجّع الكمية القديمة للأصناف اللي ما لمستها.
      if (Math.abs(quantity - line.systemQuantity) < 0.0005) {
        continue;
      }

      let unitCost: number | null = null;

      if (canViewCost && line.unitCost.trim()) {
        const cost = Number(line.unitCost);

        if (!Number.isFinite(cost) || cost < 0) {
          setCountMessage(`راجع كلفة ${line.productName}.`);
          return;
        }

        unitCost = Number(cost.toFixed(4));
      }

      items.push({
        product_id: line.productId,

        counted_quantity: Number(quantity.toFixed(3)),

        unit_cost: unitCost,
      });
    }

    if (!items.length) {
      setCountMessage("ما في ولا فرق. غيّر كمية الأصناف اللي عدّيتها ولقيتها مختلفة عن النظام.");
      return;
    }

    setSaving(true);
    setCountMessage("");

    try {
      const { error } = await supabase.rpc("post_inventory_count", {
        target_company: companyId,

        target_warehouse: countWarehouse,

        target_count_date: countDate,

        target_notes: countNotes.trim() || null,

        items_payload: items,
      });

      if (error) {
        setCountMessage(friendlyError(error, "count"));
        return;
      }

      setCountOpen(false);

      setNotice({
        type: "success",
        text: "تم ترحيل الجرد وتسجيل فروقات المخزون.",
      });

      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  // ==========================================================
  // REVERSALS
  // ==========================================================

  function openReverse(target: ReverseTarget) {
    if (target.kind === "receipt" && !canReverseReceipt) {
      return;
    }

    if (target.kind !== "receipt" && !canAdjust) {
      return;
    }

    setReverseTarget(target);

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
      setReverseMessage("اكتب سبب العكس.");
      return;
    }

    setReversing(true);

    setReverseMessage("");

    try {
      let error: {
        code?: string;
        message?: string;
      } | null = null;

      if (reverseTarget.kind === "receipt") {
        const result = await supabase.rpc("reverse_goods_receipt", {
          target_company: companyId,

          target_receipt: reverseTarget.id,

          target_reason: reason,
        });

        error = result.error;
      } else if (reverseTarget.kind === "transfer") {
        const result = await supabase.rpc("reverse_inventory_transfer", {
          target_company: companyId,

          target_transfer: reverseTarget.id,

          target_reason: reason,
        });

        error = result.error;
      } else {
        const result = await supabase.rpc("reverse_inventory_count", {
          target_company: companyId,

          target_count: reverseTarget.id,

          target_reason: reason,
        });

        error = result.error;
      }

      if (error) {
        setReverseMessage(friendlyError(error, "reverse"));
        return;
      }

      setReverseTarget(null);

      setNotice({
        type: "success",
        text: "تم تسجيل الحركة العكسية بنجاح.",
      });

      router.refresh();
    } finally {
      setReversing(false);
    }
  }

  const reverseLabel =
    reverseTarget?.kind === "receipt"
      ? "الاستلام"
      : reverseTarget?.kind === "transfer"
        ? "التحويل"
        : "الجرد";

  // ==========================================================
  // RENDER
  // ==========================================================

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">المخزون</span>

          <h2>إدارة المخزون</h2>

          <p className="muted">المخزون الفعلي، الحجوزات، الاستلام، التحويل والجرد.</p>
        </div>

        {canAdjust ? (
          <div className="rowActions">
            <button type="button" className="softButton" onClick={openWarehouse}>
              <Icons.plus size={14} />
              مستودع
            </button>

            <button
              type="button"
              className="softButton"
              disabled={warehouses.length < 2}
              onClick={openTransfer}
            >
              تحويل مخزون
            </button>

            <button type="button" className="primaryButton" onClick={() => void openCount()}>
              جرد فعلي
            </button>
          </div>
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
        <Mini title="المستودعات" value={String(stockStats.warehouseCount)} />

        <Mini title="أصناف محجوزة" value={String(stockStats.reservedLines)} />

        <Mini title="غير متاح" value={String(stockStats.outOfStock)} />

        <Mini
          title={canViewCost ? "قيمة المخزون" : "فواتير بانتظار الاستلام"}
          value={
            canViewCost
              ? money(stockStats.stockValue, currency)
              : String(stockStats.pendingReceiptInvoices)
          }
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
            <h2>المستودعات</h2>

            <p>نقاط التخزين الفعالة بالشركة.</p>
          </div>
        </div>

        {!warehouses.length ? (
          <p className="muted">لا توجد مستودعات فعالة.</p>
        ) : (
          <div className="quickList">
            {warehouses.map((warehouse) => (
              <div className="quickItem" key={warehouse.id}>
                <div className="quickIcon">
                  <Icons.box size={15} />
                </div>

                <div>
                  <strong>{warehouse.name}</strong>

                  <span>
                    {warehouse.code || "بدون كود"}

                    {warehouse.address ? ` • ${warehouse.address}` : ""}
                  </span>
                </div>

                {warehouse.is_default ? (
                  <span className="chip green">رئيسي</span>
                ) : canAdjust ? (
                  <button
                    type="button"
                    className="softButton"
                    disabled={saving}
                    onClick={() => void makeDefaultWarehouse(warehouse.id)}
                  >
                    جعله رئيسي
                  </button>
                ) : null}
              </div>
            ))}
          </div>
        )}
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

            navigateStock(search, warehouseSearch, 1);
          }}
        >
          <div className="searchBox">
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="بحث بالصنف أو الكود..."
              aria-label="بحث في المخزون"
            />

            <button type="submit" className="softButton">
              بحث
            </button>
          </div>

          <select
            value={warehouseSearch}
            aria-label="تصفية حسب المستودع"
            onChange={(event) => {
              const value = event.target.value;

              setWarehouseSearch(value);

              navigateStock(search, value, 1);
            }}
          >
            <option value="all">كل المستودعات</option>

            {warehouses.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>
            ))}
          </select>

          <div />

          <div className="resultCount">{stockTotalCount} نتيجة</div>
        </form>

        {!stock.length ? (
          <div className="empty">
            <Icons.box size={30} />

            <h3>لا توجد نتائج مخزون</h3>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الصنف</th>
                  <th>المستودع</th>
                  <th>الموجود</th>
                  <th>المحجوز</th>
                  <th>المتاح</th>

                  {canViewCost ? (
                    <>
                      <th>متوسط التكلفة</th>

                      <th>القيمة</th>
                    </>
                  ) : null}
                </tr>
              </thead>

              <tbody>
                {stock.map((row) => (
                  <tr key={`${row.warehouse_id}:${row.product_id}`}>
                    <td>
                      <strong>{row.product_name}</strong>

                      <div className="muted">
                        {row.sku || "بدون كود"}

                        {row.unit ? ` • ${row.unit}` : ""}
                      </div>
                    </td>

                    <td>{row.warehouse_name}</td>

                    <td>{qty(row.on_hand)}</td>

                    <td>{qty(row.reserved)}</td>

                    <td>
                      <span className={`chip ${numeric(row.available) > 0 ? "green" : "gray"}`}>
                        {qty(row.available)}
                      </span>
                    </td>

                    {canViewCost ? (
                      <>
                        <td>
                          {row.average_cost == null
                            ? "—"
                            : `${numeric(row.average_cost).toFixed(4)} ${currency}`}
                        </td>

                        <td>{row.stock_value == null ? "—" : money(row.stock_value, currency)}</td>
                      </>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {stockPageCount > 1 ? (
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
              disabled={stockPage <= 1}
              onClick={() => navigateStock(searchQuery, warehouseFilter, stockPage - 1)}
            >
              السابق
            </button>

            <span className="muted">
              صفحة {stockPage} من {stockPageCount}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={stockPage >= stockPageCount}
              onClick={() => navigateStock(searchQuery, warehouseFilter, stockPage + 1)}
            >
              التالي
            </button>
          </div>
        ) : null}
      </section>

      {canReceive ? (
        <section
          className="panel panelPad"
          style={{
            marginTop: 14,
          }}
        >
          <div className="panelHeader">
            <div>
              <h2>مشتريات بانتظار الاستلام</h2>

              <p>جميع فواتير الشراء التي ما زالت تحتوي على كميات غير مستلمة.</p>
            </div>
          </div>

          {!receivableInvoices.length ? (
            <p className="muted">لا توجد مشتريات معلقة للاستلام.</p>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الفاتورة</th>
                    <th>المورد</th>
                    <th>التاريخ</th>
                    <th>الأصناف</th>
                    <th>الكمية المتبقية</th>
                    <th>إجراء</th>
                  </tr>
                </thead>

                <tbody>
                  {receivableInvoices.map((invoice) => {
                    const remaining = invoice.items.reduce(
                      (total, item) => total + numeric(item.remaining_quantity),
                      0,
                    );

                    return (
                      <tr key={invoice.id}>
                        <td>
                          <strong>{invoice.invoice_number}</strong>

                          {invoice.supplier_invoice_number ? (
                            <div className="muted">مورد: {invoice.supplier_invoice_number}</div>
                          ) : null}
                        </td>

                        <td>{invoice.supplier_name}</td>

                        <td>{invoice.invoice_date}</td>

                        <td>{invoice.items.length}</td>

                        <td>
                          <strong>{qty(remaining)}</strong>
                        </td>

                        <td>
                          <button
                            type="button"
                            className="primaryButton"
                            onClick={() => openReceipt(invoice)}
                          >
                            استلام
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>
      ) : null}

      <section
        className="panel panelPad"
        style={{
          marginTop: 14,
        }}
      >
        <div className="panelHeader">
          <div>
            <h2>آخر الاستلامات</h2>

            <p>سجل استلام البضاعة من الموردين.</p>
          </div>
        </div>

        {!receipts.length ? (
          <p className="muted">لا توجد استلامات مسجلة.</p>
        ) : (
          <div className="quickList">
            {receipts.slice(0, 15).map((receipt) => (
              <div className="quickItem" key={receipt.id}>
                <div>
                  <strong>{receipt.receipt_number}</strong>

                  <span>
                    {warehouseNameById(receipt.warehouse_id)} • {receipt.receipt_date}
                  </span>

                  {receipt.cancellation_reason ? (
                    <span>السبب: {receipt.cancellation_reason}</span>
                  ) : null}
                </div>

                <div className="rowActions">
                  <span className={`chip ${receipt.status === "posted" ? "green" : "gray"}`}>
                    {statusLabel(receipt.status)}
                  </span>

                  {canReverseReceipt && receipt.status === "posted" ? (
                    <button
                      type="button"
                      className="softButton"
                      onClick={() =>
                        openReverse({
                          kind: "receipt",
                          id: receipt.id,
                          number: receipt.receipt_number,
                        })
                      }
                    >
                      عكس الاستلام
                    </button>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <div
        className="pageGrid"
        style={{
          marginTop: 14,
        }}
      >
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>آخر التحويلات</h2>
            </div>
          </div>

          {!transfers.length ? (
            <p className="muted">لا توجد تحويلات مسجلة.</p>
          ) : (
            <div className="quickList">
              {transfers.slice(0, 15).map((transfer) => (
                <div className="quickItem" key={transfer.id}>
                  <div>
                    <strong>{transfer.transfer_number}</strong>

                    <span>
                      {warehouseNameById(transfer.source_warehouse_id)} ←{" "}
                      {warehouseNameById(transfer.destination_warehouse_id)} •{" "}
                      {transfer.transfer_date}
                    </span>

                    {transfer.reversal_reason ? (
                      <span>السبب: {transfer.reversal_reason}</span>
                    ) : null}
                  </div>

                  <div className="rowActions">
                    <span className={`chip ${transfer.status === "posted" ? "green" : "gray"}`}>
                      {statusLabel(transfer.status)}
                    </span>

                    {canAdjust && transfer.status === "posted" ? (
                      <button
                        type="button"
                        className="softButton"
                        onClick={() =>
                          openReverse({
                            kind: "transfer",
                            id: transfer.id,
                            number: transfer.transfer_number,
                          })
                        }
                      >
                        عكس
                      </button>
                    ) : null}
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>آخر عمليات الجرد</h2>
            </div>
          </div>

          {!counts.length ? (
            <p className="muted">لا يوجد جرد مسجل.</p>
          ) : (
            <div className="quickList">
              {counts.slice(0, 15).map((count) => (
                <div className="quickItem" key={count.id}>
                  <div>
                    <strong>{count.count_number}</strong>

                    <span>
                      {warehouseNameById(count.warehouse_id)} • {count.count_date}
                    </span>

                    {count.reversal_reason ? <span>السبب: {count.reversal_reason}</span> : null}
                  </div>

                  <div className="rowActions">
                    <span className={`chip ${count.status === "posted" ? "green" : "gray"}`}>
                      {statusLabel(count.status)}
                    </span>

                    {canAdjust && count.status === "posted" ? (
                      <button
                        type="button"
                        className="softButton"
                        onClick={() =>
                          openReverse({
                            kind: "count",
                            id: count.id,
                            number: count.count_number,
                          })
                        }
                      >
                        عكس
                      </button>
                    ) : null}
                  </div>
                </div>
              ))}
            </div>
          )}
        </aside>
      </div>

      {warehouseOpen ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">مستودع جديد</span>

                <h2>إضافة مستودع</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setWarehouseOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveWarehouse}>
              <div className="formGrid">
                <label className="field">
                  <span>الاسم *</span>

                  <input
                    value={warehouseName}
                    onChange={(event) => setWarehouseName(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>الكود</span>

                  <input
                    value={warehouseCode}
                    onChange={(event) => setWarehouseCode(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>العنوان</span>

                  <input
                    value={warehouseAddress}
                    onChange={(event) => setWarehouseAddress(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>النوع</span>

                  <select
                    value={warehouseDefault ? "yes" : "no"}
                    onChange={(event) => setWarehouseDefault(event.target.value === "yes")}
                  >
                    <option value="no">مستودع عادي</option>

                    <option value="yes">مستودع رئيسي</option>
                  </select>
                </label>
              </div>

              {warehouseMessage ? <div className="toastError">{warehouseMessage}</div> : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setWarehouseOpen(false)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الحفظ..." : "حفظ المستودع"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {selectedInvoice ? (
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
                <span className="eyebrow">استلام بضاعة</span>

                <h2>{selectedInvoice.invoice_number}</h2>

                <p className="muted">{selectedInvoice.supplier_name}</p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setSelectedInvoice(null)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveReceipt}>
              <div className="formGrid">
                <label className="field">
                  <span>المستودع *</span>

                  <select
                    value={receiptWarehouse}
                    onChange={(event) => setReceiptWarehouse(event.target.value)}
                  >
                    <option value="">اختر</option>

                    {warehouses.map((warehouse) => (
                      <option key={warehouse.id} value={warehouse.id}>
                        {warehouse.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>تاريخ الاستلام</span>

                  <input
                    type="date"
                    value={receiptDate}
                    onChange={(event) => setReceiptDate(event.target.value)}
                  />
                </label>
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
                      <th>المشتراة</th>
                      <th>مستلمة سابقاً</th>
                      <th>المتبقي</th>
                      <th>استلام الآن</th>
                    </tr>
                  </thead>

                  <tbody>
                    {selectedInvoice.items.map((item) => (
                      <tr key={item.item_id}>
                        <td>
                          <strong>{item.product_name}</strong>

                          <div className="muted">{item.sku || "بدون كود"}</div>
                        </td>

                        <td>{qty(item.invoiced_quantity)}</td>

                        <td>{qty(item.received_quantity)}</td>

                        <td>{qty(item.remaining_quantity)}</td>

                        <td>
                          <input
                            type="number"
                            min="0"
                            max={item.remaining_quantity}
                            step="0.001"
                            value={receiptQuantities[item.item_id] ?? ""}
                            onChange={(event) =>
                              setReceiptQuantities((current) => ({
                                ...current,
                                [item.item_id]: event.target.value,
                              }))
                            }
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>ملاحظات</span>

                <textarea
                  value={receiptNotes}
                  onChange={(event) => setReceiptNotes(event.target.value)}
                />
              </label>

              {receiptMessage ? <div className="toastError">{receiptMessage}</div> : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setSelectedInvoice(null)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الاستلام..." : "تأكيد الاستلام"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {transferOpen ? (
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
              <h2>تحويل مخزون</h2>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setTransferOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveTransfer}>
              <div className="formGrid">
                <label className="field">
                  <span>من مستودع *</span>

                  <select
                    value={transferSource}
                    onChange={(event) => setTransferSource(event.target.value)}
                  >
                    {warehouses.map((warehouse) => (
                      <option key={warehouse.id} value={warehouse.id}>
                        {warehouse.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>إلى مستودع *</span>

                  <select
                    value={transferDestination}
                    onChange={(event) => setTransferDestination(event.target.value)}
                  >
                    {warehouses.map((warehouse) => (
                      <option key={warehouse.id} value={warehouse.id}>
                        {warehouse.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={transferDate}
                    onChange={(event) => setTransferDate(event.target.value)}
                  />
                </label>
              </div>

              <div
                className="quickList"
                style={{
                  marginTop: 14,
                }}
              >
                {transferLines.map((line, index) => (
                  <div className="quickItem" key={line.key}>
                    <select
                      value={line.productId}
                      onChange={(event) =>
                        setTransferLines((current) =>
                          current.map((row, rowIndex) =>
                            rowIndex === index
                              ? {
                                  ...row,
                                  productId: event.target.value,
                                }
                              : row,
                          ),
                        )
                      }
                    >
                      <option value="">اختر الصنف</option>

                      {products.map((product) => (
                        <option key={product.id} value={product.id}>
                          {product.name}
                        </option>
                      ))}
                    </select>

                    <input
                      type="number"
                      min="0.001"
                      step="0.001"
                      placeholder="الكمية"
                      value={line.quantity}
                      onChange={(event) =>
                        setTransferLines((current) =>
                          current.map((row, rowIndex) =>
                            rowIndex === index
                              ? {
                                  ...row,
                                  quantity: event.target.value,
                                }
                              : row,
                          ),
                        )
                      }
                    />

                    <button
                      type="button"
                      className="dangerButton"
                      disabled={transferLines.length === 1}
                      onClick={() =>
                        setTransferLines((current) =>
                          current.filter((_, rowIndex) => rowIndex !== index),
                        )
                      }
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>

              <button type="button" className="softButton" onClick={addTransferLine}>
                إضافة صنف
              </button>

              <label className="field">
                <span>ملاحظات</span>

                <textarea
                  value={transferNotes}
                  onChange={(event) => setTransferNotes(event.target.value)}
                />
              </label>

              {transferMessage ? <div className="toastError">{transferMessage}</div> : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setTransferOpen(false)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  {saving ? "جارٍ الترحيل..." : "ترحيل التحويل"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}

      {countOpen ? (
        <div className="modalOverlay">
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            style={{
              maxWidth: 950,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <h2>جرد فعلي</h2>

              <button
                type="button"
                className="closeButton"
                disabled={saving}
                onClick={() => setCountOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveCount}>
              <div className="formGrid">
                <label className="field">
                  <span>المستودع *</span>

                  <select
                    value={countWarehouse}
                    onChange={(event) => void loadCountWarehouse(event.target.value)}
                  >
                    {warehouses.map((warehouse) => (
                      <option key={warehouse.id} value={warehouse.id}>
                        {warehouse.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label className="field">
                  <span>التاريخ</span>

                  <input
                    type="date"
                    value={countDate}
                    onChange={(event) => setCountDate(event.target.value)}
                  />
                </label>
              </div>

              {loadingCount ? (
                <p className="muted">جارٍ تحميل رصيد المستودع...</p>
              ) : (
                <div
                  className="tableWrap"
                  style={{
                    marginTop: 14,
                    maxHeight: 430,
                    overflowY: "auto",
                  }}
                >
                  <table className="dataTable">
                    <thead>
                      <tr>
                        <th>الصنف</th>

                        <th>بالنظام</th>

                        <th>الكمية الفعلية</th>

                        <th>الفرق</th>

                        {canViewCost ? <th>كلفة المخزون الجديد فقط</th> : null}
                      </tr>
                    </thead>

                    <tbody>
                      {countLines.map((line, index) => (
                        <tr key={line.productId}>
                          <td>
                            <strong>{line.productName}</strong>

                            <div className="muted">{line.sku || "بدون كود"}</div>
                          </td>

                          <td className="muted">{qty(line.systemQuantity)}</td>
                          <td>
                            <input
                              type="number"
                              min="0"
                              step="0.001"
                              value={line.countedQuantity}
                              onChange={(event) =>
                                setCountLines((current) =>
                                  current.map((row, rowIndex) =>
                                    rowIndex === index
                                      ? {
                                          ...row,
                                          countedQuantity: event.target.value,
                                        }
                                      : row,
                                  ),
                                )
                              }
                            />
                          </td>

                          <td>
                            {(() => {
                              const diff = Number(line.countedQuantity || 0) - line.systemQuantity;

                              if (Math.abs(diff) < 0.0005) return <span className="muted">—</span>;

                              return (
                                <span className={`chip ${diff > 0 ? "green" : "orange"}`}>
                                  {diff > 0 ? "+" : ""}

                                  {qty(diff)}
                                </span>
                              );
                            })()}
                          </td>

                          {canViewCost ? (
                            <td>
                              <input
                                type="number"
                                min="0"
                                step="0.0001"
                                value={line.unitCost}
                                placeholder="تلقائي"
                                onChange={(event) =>
                                  setCountLines((current) =>
                                    current.map((row, rowIndex) =>
                                      rowIndex === index
                                        ? {
                                            ...row,
                                            unitCost: event.target.value,
                                          }
                                        : row,
                                    ),
                                  )
                                }
                              />
                            </td>
                          ) : null}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>ملاحظات</span>

                <textarea
                  value={countNotes}
                  onChange={(event) => setCountNotes(event.target.value)}
                />
              </label>

              {countMessage ? <div className="toastError">{countMessage}</div> : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() => setCountOpen(false)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving || loadingCount}>
                  {saving ? "جارٍ الترحيل..." : "ترحيل الجرد"}
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
              <h2>عكس {reverseLabel}</h2>
            </div>

            <form onSubmit={saveReverse}>
              <p>
                المستند: <strong>{reverseTarget.number}</strong>
              </p>

              <p className="muted">سيتم تسجيل حركة عكسية ولن يتم حذف السجل الأصلي.</p>

              <label className="field">
                <span>سبب العكس *</span>

                <textarea
                  value={reverseReason}
                  onChange={(event) => setReverseReason(event.target.value)}
                />
              </label>

              {reverseMessage ? <div className="toastError">{reverseMessage}</div> : null}

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
