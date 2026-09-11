"use client";

import {
  useMemo,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

type Relation<T> =
  | T
  | T[]
  | null;

function one<T>(
  value: Relation<T>
) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

function num(
  value: unknown
) {
  const n =
    Number(value || 0);

  return Number.isFinite(n)
    ? n
    : 0;
}

function today() {
  return new Date()
    .toISOString()
    .slice(0, 10);
}

type NameRelation = {
  id: string;
  name: string;
};

type ProductRelation = {
  id: string;
  name: string;
  sku: string | null;
};

export type ReturnWarehouse = {
  id: string;
  name: string;
  code: string | null;
  is_default: boolean;
  active: boolean;
};

export type ReturnSalesInvoiceItem = {
  id: string;
  product_id: string;
  description: string;
  unit: string | null;
  quantity: number;
  unit_price: number;
  line_total: number;
  products:
    Relation<ProductRelation>;
};

export type ReturnSalesInvoice = {
  id: string;
  invoice_number: string;
  trader_id: string;
  invoice_date: string;
  currency: string;
  subtotal: number;
  discount_total: number;
  total: number;
  status: string;
  traders:
    Relation<NameRelation>;
  sales_invoice_items:
    ReturnSalesInvoiceItem[];
};

export type ReturnPurchaseInvoiceItem = {
  id: string;
  product_id: string;
  description: string | null;
  quantity: number;
  unit_cost: number;
  line_total: number;
  products:
    Relation<ProductRelation>;
};

export type ReturnPurchaseInvoice = {
  id: string;
  invoice_number: string;
  supplier_invoice_number: string | null;
  supplier_id: string;
  invoice_date: string;
  currency: string;
  total: number;
  status: string;
  suppliers:
    Relation<NameRelation>;
  purchase_invoice_items:
    ReturnPurchaseInvoiceItem[];
};

export type SalesReturnRecord = {
  id: string;
  return_number: string;
  sales_invoice_id: string;
  trader_id: string;
  warehouse_id: string;
  return_date: string;
  status: string;
  currency: string;
  subtotal: number;
  discount_total: number;
  total: number;
  notes: string | null;
  created_at: string;
};

export type PurchaseReturnRecord = {
  id: string;
  return_number: string;
  purchase_invoice_id: string;
  supplier_id: string;
  warehouse_id: string;
  return_date: string;
  status: string;
  currency: string;
  inventory_cost_total: number;
  total: number;
  notes: string | null;
  created_at: string;
};

type Tab =
  | "sales"
  | "purchases"
  | "history";

export function ReturnsClient({
  companyId,
  baseCurrency,
  warehouses,
  salesInvoices,
  purchaseInvoices,
  salesReturns,
  purchaseReturns,
  salesReturnItems,
  purchaseReturnItems,
  canCreate,
  canReverse,
}: {
  companyId: string;
  baseCurrency: string;
  warehouses: ReturnWarehouse[];
  salesInvoices: ReturnSalesInvoice[];
  purchaseInvoices: ReturnPurchaseInvoice[];
  salesReturns: SalesReturnRecord[];
  purchaseReturns: PurchaseReturnRecord[];
  salesReturnItems: {
    id: string;
    sales_return_id: string;
    sales_invoice_item_id: string;
    quantity: number;
  }[];
  purchaseReturnItems: {
    id: string;
    purchase_return_id: string;
    purchase_invoice_item_id: string;
    quantity: number;
  }[];
  canCreate: boolean;
  canReverse: boolean;
}) {
  const [supabase] =
    useState(() => createClient());

  const router = useRouter();

  const [tab, setTab] =
    useState<Tab>("sales");

  const [search, setSearch] =
    useState("");

  const [
    salesOpen,
    setSalesOpen,
  ] = useState(false);

  const [
    purchaseOpen,
    setPurchaseOpen,
  ] = useState(false);

  const [
    salesInvoiceId,
    setSalesInvoiceId,
  ] = useState("");

  const [
    purchaseInvoiceId,
    setPurchaseInvoiceId,
  ] = useState("");

  const [
    warehouseId,
    setWarehouseId,
  ] = useState(
    warehouses.find(
      (warehouse) =>
        warehouse.is_default
    )?.id ||
      warehouses[0]?.id ||
      ""
  );

  const [
    returnDate,
    setReturnDate,
  ] = useState(today());

  const [notes, setNotes] =
    useState("");

  const [
    quantities,
    setQuantities,
  ] = useState<
    Record<string, string>
  >({});

  const [saving, setSaving] =
    useState(false);

  const [message, setMessage] =
    useState("");

  const [
    busyReturn,
    setBusyReturn,
  ] = useState<string | null>(null);

  const activeSalesReturnIds =
    useMemo(
      () =>
        new Set(
          salesReturns
            .filter(
              (item) =>
                item.status ===
                "posted"
            )
            .map(
              (item) =>
                item.id
            )
        ),
      [salesReturns]
    );

  const activePurchaseReturnIds =
    useMemo(
      () =>
        new Set(
          purchaseReturns
            .filter(
              (item) =>
                item.status ===
                "posted"
            )
            .map(
              (item) =>
                item.id
            )
        ),
      [purchaseReturns]
    );

  function returnedSalesQty(
    itemId: string
  ) {
    return salesReturnItems
      .filter(
        (row) =>
          row.sales_invoice_item_id ===
            itemId &&
          activeSalesReturnIds.has(
            row.sales_return_id
          )
      )
      .reduce(
        (sum, row) =>
          sum +
          num(
            row.quantity
          ),
        0
      );
  }

  function returnedPurchaseQty(
    itemId: string
  ) {
    return purchaseReturnItems
      .filter(
        (row) =>
          row.purchase_invoice_item_id ===
            itemId &&
          activePurchaseReturnIds.has(
            row.purchase_return_id
          )
      )
      .reduce(
        (sum, row) =>
          sum +
          num(
            row.quantity
          ),
        0
      );
  }

  const selectedSalesInvoice =
    salesInvoices.find(
      (invoice) =>
        invoice.id ===
        salesInvoiceId
    ) || null;

  const selectedPurchaseInvoice =
    purchaseInvoices.find(
      (invoice) =>
        invoice.id ===
        purchaseInvoiceId
    ) || null;

  const filteredSalesInvoices =
    salesInvoices.filter(
      (invoice) => {
        const trader =
          one(
            invoice.traders
          );

        const text =
          `${invoice.invoice_number} ${trader?.name || ""}`
            .toLowerCase();

        return text.includes(
          search
            .trim()
            .toLowerCase()
        );
      }
    );

  const filteredPurchaseInvoices =
    purchaseInvoices.filter(
      (invoice) => {
        const supplier =
          one(
            invoice.suppliers
          );

        const text =
          `${invoice.invoice_number} ${invoice.supplier_invoice_number || ""} ${supplier?.name || ""}`
            .toLowerCase();

        return text.includes(
          search
            .trim()
            .toLowerCase()
        );
      }
    );

  const salesReturnTotal =
    salesReturns
      .filter(
        (item) =>
          item.status ===
          "posted"
      )
      .reduce(
        (sum, item) =>
          sum +
          num(
            item.total
          ),
        0
      );

  const purchaseReturnTotal =
    purchaseReturns
      .filter(
        (item) =>
          item.status ===
          "posted"
      )
      .reduce(
        (sum, item) =>
          sum +
          num(
            item.total
          ),
        0
      );

  function startSalesReturn(
    invoice: ReturnSalesInvoice
  ) {
    const initial: Record<
      string,
      string
    > = {};

    for (const item of
      invoice.sales_invoice_items) {
      initial[item.id] = "";
    }

    setSalesInvoiceId(
      invoice.id
    );

    setPurchaseInvoiceId(
      ""
    );

    setQuantities(
      initial
    );

    setReturnDate(
      today()
    );

    setNotes("");
    setMessage("");
    setSalesOpen(true);
  }

  function startPurchaseReturn(
    invoice: ReturnPurchaseInvoice
  ) {
    const initial: Record<
      string,
      string
    > = {};

    for (const item of
      invoice.purchase_invoice_items) {
      initial[item.id] = "";
    }

    setPurchaseInvoiceId(
      invoice.id
    );

    setSalesInvoiceId(
      ""
    );

    setQuantities(
      initial
    );

    setReturnDate(
      today()
    );

    setNotes("");
    setMessage("");
    setPurchaseOpen(
      true
    );
  }

  async function saveSalesReturn(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !selectedSalesInvoice ||
      !warehouseId
    ) {
      setMessage(
        "اختار الفاتورة والمستودع."
      );
      return;
    }

    const items =
      selectedSalesInvoice.sales_invoice_items
        .map((item) => ({
          sales_invoice_item_id:
            item.id,
          quantity:
            num(
              quantities[
                item.id
              ]
            ),
          max:
            Math.max(
              num(
                item.quantity
              ) -
                returnedSalesQty(
                  item.id
                ),
              0
            ),
        }))
        .filter(
          (item) =>
            item.quantity >
            0
        );

    if (!items.length) {
      setMessage(
        "اكتب كمية مرتجعة لمنتج واحد على الأقل."
      );
      return;
    }

    if (
      items.some(
        (item) =>
          item.quantity >
          item.max
      )
    ) {
      setMessage(
        "في كمية أكبر من الكمية المتبقية القابلة للإرجاع."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "create_sales_return",
        {
          target_company:
            companyId,

          target_invoice:
            selectedSalesInvoice.id,

          target_warehouse:
            warehouseId,

          target_date:
            returnDate,

          target_notes:
            notes.trim() ||
            null,

          items_payload:
            items.map(
              ({
                sales_invoice_item_id,
                quantity,
              }) => ({
                sales_invoice_item_id,
                quantity,
              })
            ),
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setSalesOpen(false);
    router.refresh();
  }

  async function savePurchaseReturn(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !selectedPurchaseInvoice ||
      !warehouseId
    ) {
      setMessage(
        "اختار الفاتورة والمستودع."
      );
      return;
    }

    const items =
      selectedPurchaseInvoice.purchase_invoice_items
        .map((item) => ({
          purchase_invoice_item_id:
            item.id,

          quantity:
            num(
              quantities[
                item.id
              ]
            ),

          max:
            Math.max(
              num(
                item.quantity
              ) -
                returnedPurchaseQty(
                  item.id
                ),
              0
            ),
        }))
        .filter(
          (item) =>
            item.quantity >
            0
        );

    if (!items.length) {
      setMessage(
        "اكتب كمية مرتجعة لمنتج واحد على الأقل."
      );
      return;
    }

    if (
      items.some(
        (item) =>
          item.quantity >
          item.max
      )
    ) {
      setMessage(
        "في كمية أكبر من الكمية المتبقية القابلة للإرجاع."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "create_purchase_return",
        {
          target_company:
            companyId,

          target_invoice:
            selectedPurchaseInvoice.id,

          target_warehouse:
            warehouseId,

          target_date:
            returnDate,

          target_notes:
            notes.trim() ||
            null,

          items_payload:
            items.map(
              ({
                purchase_invoice_item_id,
                quantity,
              }) => ({
                purchase_invoice_item_id,
                quantity,
              })
            ),
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setPurchaseOpen(false);
    router.refresh();
  }

  const tabButton = (
    key: Tab,
    label: string
  ) => (
    <button
      type="button"
      className={
        tab === key
          ? "primaryButton"
          : "softButton"
      }
      onClick={() =>
        setTab(key)
      }
    >
      {label}
    </button>
  );
  function returnStatusLabel(
    status: string
  ) {
    if (status === "posted") {
      return "مرحّل";
    }

    if (status === "reversed") {
      return "معكوس";
    }

    return "ملغى";
  }

  async function reverseReturn(
    kind: "sales" | "purchases",
    id: string,
    number: string
  ) {
    if (!canReverse) {
      return;
    }

    const reason =
      window.prompt(
        `سبب عكس المرتجع ${number}:`
      );

    if (reason === null) {
      return;
    }

    if (!reason.trim()) {
      window.alert(
        "اكتب سبب عكس المرتجع."
      );
      return;
    }

    const confirmed =
      window.confirm(
        `تأكيد عكس المرتجع ${number}؟ سيتم عكس حركة المخزون والقيد المحاسبي.`
      );

    if (!confirmed) {
      return;
    }

    setBusyReturn(id);

    const { error } =
      await supabase.rpc(
        kind === "sales"
          ? "reverse_sales_return"
          : "reverse_purchase_return",
        {
          target_company:
            companyId,

          target_return:
            id,

          target_reason:
            reason.trim(),
        }
      );

    setBusyReturn(null);

    if (error) {
      window.alert(
        error.message
      );
      return;
    }

    router.refresh();

    window.setTimeout(
      () =>
        window.location.reload(),
      100
    );
  }


  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Returns Center
          </span>

          <h2>
            المرتجعات
          </h2>

          <p className="muted">
            مرتجعات العملاء والموردين مرتبطة بالمخزون والمحاسبة تلقائيًا.
          </p>
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="مرتجعات مبيعات"
          value={String(
            salesReturns.length
          )}
        />

        <Mini
          title="قيمة مرتجعات المبيعات"
          value={`${salesReturnTotal.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="مرتجعات مشتريات"
          value={String(
            purchaseReturns.length
          )}
        />

        <Mini
          title="قيمة مرتجعات المشتريات"
          value={`${purchaseReturnTotal.toFixed(
            2
          )} ${baseCurrency}`}
        />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        {tabButton(
          "sales",
          "مرتجع مبيعات"
        )}

        {tabButton(
          "purchases",
          "مرتجع مشتريات"
        )}

        {tabButton(
          "history",
          "سجل المرتجعات"
        )}
      </div>

      {tab !== "history" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <div className="filters">
            <div className="searchBox">
              <Icons.search
                size={16}
              />

              <input
                value={search}
                onChange={(
                  event
                ) =>
                  setSearch(
                    event.target
                      .value
                  )
                }
                placeholder={
                  tab === "sales"
                    ? "بحث برقم فاتورة البيع أو العميل..."
                    : "بحث برقم فاتورة الشراء أو المورد..."
                }
              />
            </div>
          </div>

          {tab ===
            "sales" && (
            <InvoiceSalesTable
              invoices={
                filteredSalesInvoices
              }
              returnedQuantity={
                returnedSalesQty
              }
              canCreate={
                canCreate
              }
              onReturn={
                startSalesReturn
              }
            />
          )}

          {tab ===
            "purchases" && (
            <InvoicePurchaseTable
              invoices={
                filteredPurchaseInvoices
              }
              returnedQuantity={
                returnedPurchaseQty
              }
              canCreate={
                canCreate
              }
              onReturn={
                startPurchaseReturn
              }
            />
          )}
        </section>
      )}

      {tab ===
        "history" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>رقم المرتجع</th>
                  <th>النوع</th>
                  <th>الفاتورة</th>
                  <th>التاريخ</th>
                  <th>المبلغ</th>
                  <th>الحالة</th>
                </tr>
              </thead>

              <tbody>
                {[
                  ...salesReturns.map(
                    (item) => ({
                      id:
                        item.id,
                      number:
                        item.return_number,
                      type:
                        "مبيعات",
                      invoice:
                        salesInvoices.find(
                          (
                            invoice
                          ) =>
                            invoice.id ===
                            item.sales_invoice_id
                        )
                          ?.invoice_number ||
                        "—",
                      date:
                        item.return_date,
                      total:
                        item.total,
                      currency:
                        item.currency,
                      status:
                        item.status,
                    })
                  ),

                  ...purchaseReturns.map(
                    (item) => ({
                      id:
                        item.id,
                      number:
                        item.return_number,
                      type:
                        "مشتريات",
                      invoice:
                        purchaseInvoices.find(
                          (
                            invoice
                          ) =>
                            invoice.id ===
                            item.purchase_invoice_id
                        )
                          ?.invoice_number ||
                        "—",
                      date:
                        item.return_date,
                      total:
                        item.total,
                      currency:
                        item.currency,
                      status:
                        item.status,
                    })
                  ),
                ]
                  .sort(
                    (a, b) =>
                      b.date.localeCompare(
                        a.date
                      )
                  )
                  .map(
                    (item) => (
                      <tr
                        key={
                          item.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              item.number
                            }
                          </strong>
                        </td>

                        <td>
                          {
                            item.type
                          }
                        </td>

                        <td>
                          {
                            item.invoice
                          }
                        </td>

                        <td>
                          {
                            item.date
                          }
                        </td>

                        <td>
                          {num(
                            item.total
                          ).toFixed(
                            2
                          )}{" "}
                          {
                            item.currency
                          }
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              item.status ===
                              "posted"
                                ? "green"
                                : "gray"
                            }`}
                          >
                            {returnStatusLabel(item.status)}
                          </span>
                        </td>

                        <td>
                          {canReverse && item.status === "posted" ? (
                            <button
                              type="button"
                              className="softButton"
                              data-return-reverse-action="true"
                              disabled={busyReturn === item.id}
                              onClick={() =>
                                void reverseReturn(
                                  item.type === "??????"
                                    ? "sales"
                                    : "purchases",
                                  item.id,
                                  item.number
                                )
                              }
                            >
                              {busyReturn === item.id
                                ? "?? ????..."
                                : "??? ???????"}
                            </button>
                          ) : (
                            "?"
                          )}
                        </td>
                      </tr>
                    )
                  )}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {salesOpen &&
        selectedSalesInvoice && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 900,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Sales Return
                </span>

                <h2>
                  مرتجع فاتورة{" "}
                  {
                    selectedSalesInvoice.invoice_number
                  }
                </h2>

                <p className="muted">
                  {one(
                    selectedSalesInvoice.traders
                  )?.name ||
                    "عميل"}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setSalesOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveSalesReturn
              }
            >
              <ReturnHeader
                warehouses={
                  warehouses
                }
                warehouseId={
                  warehouseId
                }
                setWarehouseId={
                  setWarehouseId
                }
                date={
                  returnDate
                }
                setDate={
                  setReturnDate
                }
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
                      <th>المنتج</th>
                      <th>المباع</th>
                      <th>مرتجع سابق</th>
                      <th>متاح للإرجاع</th>
                      <th>الكمية</th>
                    </tr>
                  </thead>

                  <tbody>
                    {selectedSalesInvoice.sales_invoice_items.map(
                      (item) => {
                        const returned =
                          returnedSalesQty(
                            item.id
                          );

                        const available =
                          Math.max(
                            num(
                              item.quantity
                            ) -
                              returned,
                            0
                          );

                        return (
                          <tr
                            key={
                              item.id
                            }
                          >
                            <td>
                              <strong>
                                {one(
                                  item.products
                                )?.name ||
                                  item.description}
                              </strong>
                            </td>

                            <td>
                              {num(
                                item.quantity
                              )}
                            </td>

                            <td>
                              {
                                returned
                              }
                            </td>

                            <td>
                              {
                                available
                              }
                            </td>

                            <td>
                              <input
                                type="number"
                                min="0"
                                max={
                                  available
                                }
                                step="0.001"
                                disabled={
                                  available <=
                                  0
                                }
                                value={
                                  quantities[
                                    item.id
                                  ] ||
                                  ""
                                }
                                onChange={(
                                  event
                                ) =>
                                  setQuantities(
                                    (
                                      current
                                    ) => ({
                                      ...current,
                                      [item.id]:
                                        event.target.value,
                                    })
                                  )
                                }
                                style={{
                                  minWidth:
                                    100,
                                }}
                              />
                            </td>
                          </tr>
                        );
                      }
                    )}
                  </tbody>
                </table>
              </div>

              <Notes
                value={notes}
                setValue={
                  setNotes
                }
              />

              {message && (
                <div className="toastError">
                  {
                    message
                  }
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setSalesOpen(
                      false
                    )
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  ترحيل مرتجع المبيعات
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {purchaseOpen &&
        selectedPurchaseInvoice && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 900,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Purchase Return
                </span>

                <h2>
                  مرتجع فاتورة{" "}
                  {
                    selectedPurchaseInvoice.invoice_number
                  }
                </h2>

                <p className="muted">
                  {one(
                    selectedPurchaseInvoice.suppliers
                  )?.name ||
                    "مورد"}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setPurchaseOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                savePurchaseReturn
              }
            >
              <ReturnHeader
                warehouses={
                  warehouses
                }
                warehouseId={
                  warehouseId
                }
                setWarehouseId={
                  setWarehouseId
                }
                date={
                  returnDate
                }
                setDate={
                  setReturnDate
                }
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
                      <th>المنتج</th>
                      <th>المشترى</th>
                      <th>مرتجع سابق</th>
                      <th>متاح للإرجاع</th>
                      <th>الكمية</th>
                    </tr>
                  </thead>

                  <tbody>
                    {selectedPurchaseInvoice.purchase_invoice_items.map(
                      (item) => {
                        const returned =
                          returnedPurchaseQty(
                            item.id
                          );

                        const available =
                          Math.max(
                            num(
                              item.quantity
                            ) -
                              returned,
                            0
                          );

                        return (
                          <tr
                            key={
                              item.id
                            }
                          >
                            <td>
                              <strong>
                                {one(
                                  item.products
                                )?.name ||
                                  item.description ||
                                  "منتج"}
                              </strong>
                            </td>

                            <td>
                              {num(
                                item.quantity
                              )}
                            </td>

                            <td>
                              {
                                returned
                              }
                            </td>

                            <td>
                              {
                                available
                              }
                            </td>

                            <td>
                              <input
                                type="number"
                                min="0"
                                max={
                                  available
                                }
                                step="0.001"
                                disabled={
                                  available <=
                                  0
                                }
                                value={
                                  quantities[
                                    item.id
                                  ] ||
                                  ""
                                }
                                onChange={(
                                  event
                                ) =>
                                  setQuantities(
                                    (
                                      current
                                    ) => ({
                                      ...current,
                                      [item.id]:
                                        event.target.value,
                                    })
                                  )
                                }
                                style={{
                                  minWidth:
                                    100,
                                }}
                              />
                            </td>
                          </tr>
                        );
                      }
                    )}
                  </tbody>
                </table>
              </div>

              <Notes
                value={notes}
                setValue={
                  setNotes
                }
              />

              {message && (
                <div className="toastError">
                  {
                    message
                  }
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setPurchaseOpen(
                      false
                    )
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  ترحيل مرتجع المشتريات
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}

function InvoiceSalesTable({
  invoices,
  returnedQuantity,
  canCreate,
  onReturn,
}: {
  invoices: ReturnSalesInvoice[];
  returnedQuantity:
    (itemId: string) => number;
  canCreate: boolean;
  onReturn:
    (invoice: ReturnSalesInvoice) => void;
}) {
  if (!invoices.length) {
    return (
      <div className="empty">
        <Icons.box
          size={28}
        />

        <h3>
          ما في فواتير بيع
        </h3>
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
            <th>بنود قابلة للإرجاع</th>
            <th />
          </tr>
        </thead>

        <tbody>
          {invoices.map(
            (invoice) => {
              const availableItems =
                invoice.sales_invoice_items.filter(
                  (item) =>
                    num(
                      item.quantity
                    ) -
                      returnedQuantity(
                        item.id
                      ) >
                    0
                ).length;

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
                    {one(
                      invoice.traders
                    )?.name ||
                      "—"}
                  </td>

                  <td>
                    {
                      invoice.invoice_date
                    }
                  </td>

                  <td>
                    {num(
                      invoice.total
                    ).toFixed(
                      2
                    )}{" "}
                    {
                      invoice.currency
                    }
                  </td>

                  <td>
                    {
                      availableItems
                    }
                  </td>

                  <td>
                    {canCreate &&
                      availableItems >
                        0 && (
                        <button
                          type="button"
                          className="primaryButton"
                          onClick={() =>
                            onReturn(
                              invoice
                            )
                          }
                        >
                          مرتجع
                        </button>
                      )}
                  </td>
                </tr>
              );
            }
          )}
        </tbody>
      </table>
    </div>
  );
}

function InvoicePurchaseTable({
  invoices,
  returnedQuantity,
  canCreate,
  onReturn,
}: {
  invoices: ReturnPurchaseInvoice[];
  returnedQuantity:
    (itemId: string) => number;
  canCreate: boolean;
  onReturn:
    (invoice: ReturnPurchaseInvoice) => void;
}) {
  if (!invoices.length) {
    return (
      <div className="empty">
        <Icons.box
          size={28}
        />

        <h3>
          ما في فواتير شراء
        </h3>
      </div>
    );
  }

  return (
    <div className="tableWrap">
      <table className="dataTable">
        <thead>
          <tr>
            <th>الفاتورة</th>
            <th>المورد</th>
            <th>التاريخ</th>
            <th>القيمة</th>
            <th>بنود قابلة للإرجاع</th>
            <th />
          </tr>
        </thead>

        <tbody>
          {invoices.map(
            (invoice) => {
              const availableItems =
                invoice.purchase_invoice_items.filter(
                  (item) =>
                    num(
                      item.quantity
                    ) -
                      returnedQuantity(
                        item.id
                      ) >
                    0
                ).length;

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

                    <div className="muted">
                      {invoice.supplier_invoice_number ||
                        ""}
                    </div>
                  </td>

                  <td>
                    {one(
                      invoice.suppliers
                    )?.name ||
                      "—"}
                  </td>

                  <td>
                    {
                      invoice.invoice_date
                    }
                  </td>

                  <td>
                    {num(
                      invoice.total
                    ).toFixed(
                      2
                    )}{" "}
                    {
                      invoice.currency
                    }
                  </td>

                  <td>
                    {
                      availableItems
                    }
                  </td>

                  <td>
                    {canCreate &&
                      availableItems >
                        0 && (
                        <button
                          type="button"
                          className="primaryButton"
                          onClick={() =>
                            onReturn(
                              invoice
                            )
                          }
                        >
                          مرتجع
                        </button>
                      )}
                  </td>
                </tr>
              );
            }
          )}
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
}: {
  warehouses: ReturnWarehouse[];
  warehouseId: string;
  setWarehouseId:
    (value: string) => void;
  date: string;
  setDate:
    (value: string) => void;
}) {
  return (
    <div className="formGrid">
      <label className="field">
        <span>
          المستودع
        </span>

        <select
          value={
            warehouseId
          }
          onChange={(
            event
          ) =>
            setWarehouseId(
              event.target
                .value
            )
          }
        >
          {warehouses.map(
            (warehouse) => (
              <option
                key={
                  warehouse.id
                }
                value={
                  warehouse.id
                }
              >
                {
                  warehouse.name
                }
                {warehouse.is_default
                  ? " - الرئيسي"
                  : ""}
              </option>
            )
          )}
        </select>
      </label>

      <label className="field">
        <span>
          تاريخ المرتجع
        </span>

        <input
          type="date"
          value={date}
          onChange={(
            event
          ) =>
            setDate(
              event.target
                .value
            )
          }
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
  setValue:
    (value: string) => void;
}) {
  return (
    <label
      className="field"
      style={{
        marginTop: 14,
      }}
    >
      <span>
        سبب / ملاحظات المرتجع
      </span>

      <textarea
        rows={3}
        value={value}
        onChange={(
          event
        ) =>
          setValue(
            event.target
              .value
          )
        }
      />
    </label>
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