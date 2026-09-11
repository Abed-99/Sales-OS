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

function oneRelation<T>(
  value: Relation<T>
) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

function numeric(
  value: unknown
) {
  const result =
    Number(value || 0);

  return Number.isFinite(
    result
  )
    ? result
    : 0;
}

function todayInput() {
  return new Date()
    .toISOString()
    .slice(0, 10);
}

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
  average_cost: number;
  stock_value: number;
  updated_at: string;
};

type SupplierRelation = {
  id: string;
  name: string;
};

type ProductRelation = {
  name: string;
  sku: string | null;
  unit: string | null;
};

export type InventoryPurchaseItem = {
  id: string;
  product_id: string;
  description: string | null;
  quantity: number;
  unit_cost: number;
  products:
    Relation<ProductRelation>;
};

export type InventoryPurchaseInvoice = {
  id: string;
  supplier_id: string;
  invoice_number: string;
  supplier_invoice_number:
    string | null;
  currency: string;
  invoice_date: string;
  total: number;
  status: string;
  suppliers:
    Relation<SupplierRelation>;
  purchase_invoice_items:
    InventoryPurchaseItem[];
};

type ReceiptRelation = {
  id: string;
  status: string;
};

export type InventoryReceiptItem = {
  id: string;
  purchase_invoice_item_id: string;
  quantity: number;
  goods_receipts:
    Relation<ReceiptRelation>;
};

export type InventoryReceiptRow = {
  id: string;
  receipt_number: string;
  warehouse_id: string;
  purchase_invoice_id: string | null;
  status: string;
  receipt_date: string;
  notes: string | null;
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
  created_at: string;
};

export type InventoryCountRow = {
  id: string;
  warehouse_id: string;
  count_number: string;
  count_date: string;
  status: string;
  notes: string | null;
  created_at: string;
};

type TransferDraft = {
  productId: string;
  quantity: string;
};

type CountDraft = {
  productId: string;
  countedQuantity: string;
  unitCost: string;
};

export function InventoryClient({
  companyId,
  currency,
  warehouses,
  stock,
  products,
  purchaseInvoices,
  receiptItems,
  receipts,
  transfers,
  counts,
  canReceive,
  canReverseReceipt,
  canAdjust,
  canViewCost,
}: {
  companyId: string;
  currency: string;
  warehouses:
    InventoryWarehouse[];
  stock:
    InventoryStockRow[];
  products:
    InventoryProduct[];
  purchaseInvoices:
    InventoryPurchaseInvoice[];
  receiptItems:
    InventoryReceiptItem[];
  receipts:
    InventoryReceiptRow[];
  transfers:
    InventoryTransferRow[];
  counts:
    InventoryCountRow[];
  canReceive: boolean;
  canReverseReceipt: boolean;
  canAdjust: boolean;
  canViewCost: boolean;
}) {
  const [supabase] =
    useState(
      () => createClient()
    );

  const router =
    useRouter();

  const [
    warehouseFilter,
    setWarehouseFilter,
  ] = useState("all");

  const [
    search,
    setSearch,
  ] = useState("");

  const [
    saving,
    setSaving,
  ] = useState(false);

  const [
    message,
    setMessage,
  ] = useState("");

  const [
    reversingId,
    setReversingId,
  ] = useState<string | null>(
    null
  );

  const [
    selectedInvoice,
    setSelectedInvoice,
  ] =
    useState<
      InventoryPurchaseInvoice | null
    >(null);

  const [
    receiptWarehouse,
    setReceiptWarehouse,
  ] = useState("");

  const [
    receiptDate,
    setReceiptDate,
  ] = useState(
    todayInput()
  );

  const [
    receiptNotes,
    setReceiptNotes,
  ] = useState("");

  const [
    receiptQuantities,
    setReceiptQuantities,
  ] =
    useState<
      Record<string, string>
    >({});

  const [
    warehouseOpen,
    setWarehouseOpen,
  ] = useState(false);

  const [
    warehouseName,
    setWarehouseName,
  ] = useState("");

  const [
    warehouseCode,
    setWarehouseCode,
  ] = useState("");

  const [
    warehouseAddress,
    setWarehouseAddress,
  ] = useState("");

  const [
    warehouseDefault,
    setWarehouseDefault,
  ] = useState(false);

  const [
    transferOpen,
    setTransferOpen,
  ] = useState(false);

  const [
    transferSource,
    setTransferSource,
  ] = useState("");

  const [
    transferDestination,
    setTransferDestination,
  ] = useState("");

  const [
    transferDate,
    setTransferDate,
  ] = useState(
    todayInput()
  );

  const [
    transferNotes,
    setTransferNotes,
  ] = useState("");

  const [
    transferLines,
    setTransferLines,
  ] =
    useState<
      TransferDraft[]
    >([
      {
        productId: "",
        quantity: "",
      },
    ]);

  const [
    countOpen,
    setCountOpen,
  ] = useState(false);

  const [
    countWarehouse,
    setCountWarehouse,
  ] = useState("");

  const [
    countDate,
    setCountDate,
  ] = useState(
    todayInput()
  );

  const [
    countNotes,
    setCountNotes,
  ] = useState("");

  const [
    countLines,
    setCountLines,
  ] =
    useState<
      CountDraft[]
    >([]);

  const receivedByItem =
    useMemo(() => {
      const map =
        new Map<
          string,
          number
        >();

      for (
        const row of
        receiptItems
      ) {
        const receipt =
          oneRelation(
            row.goods_receipts
          );

        if (
          receipt?.status !==
          "posted"
        ) {
          continue;
        }

        map.set(
          row.purchase_invoice_item_id,
          (
            map.get(
              row.purchase_invoice_item_id
            ) || 0
          ) +
            numeric(
              row.quantity
            )
        );
      }

      return map;
    }, [receiptItems]);

  function remainingPurchaseItem(
    item:
      InventoryPurchaseItem
  ) {
    return Math.max(
      0,
      numeric(
        item.quantity
      ) -
        (
          receivedByItem.get(
            item.id
          ) || 0
        )
    );
  }

  const pendingInvoices =
    useMemo(
      () =>
        purchaseInvoices.filter(
          (invoice) =>
            invoice
              .purchase_invoice_items
              .some(
                (item) =>
                  remainingPurchaseItem(
                    item
                  ) > 0
              )
        ),
      [
        purchaseInvoices,
        receivedByItem,
      ]
    );

  const filteredStock =
    useMemo(() => {
      const q =
        search
          .trim()
          .toLowerCase();

      return stock.filter(
        (row) => {
          if (
            warehouseFilter !==
              "all" &&
            row.warehouse_id !==
              warehouseFilter
          ) {
            return false;
          }

          if (!q) {
            return true;
          }

          return [
            row.product_name,
            row.sku,
            row.warehouse_name,
          ].some(
            (value) =>
              value
                ?.toLowerCase()
                .includes(q)
          );
        }
      );
    }, [
      stock,
      search,
      warehouseFilter,
    ]);

  const stockValue =
    filteredStock.reduce(
      (sum, row) =>
        sum +
        numeric(
          row.stock_value
        ),
      0
    );

  const reservedLines =
    filteredStock.filter(
      (row) =>
        numeric(
          row.reserved
        ) > 0
    ).length;

  const outOfStock =
    filteredStock.filter(
      (row) =>
        numeric(
          row.available
        ) <= 0
    ).length;

  function warehouseNameById(
    id: string
  ) {
    return (
      warehouses.find(
        (row) =>
          row.id === id
      )?.name ||
      "مستودع"
    );
  }

  function stockFor(
    warehouseId: string,
    productId: string
  ) {
    return stock.find(
      (row) =>
        row.warehouse_id ===
          warehouseId &&
        row.product_id ===
          productId
    );
  }

    function openReceipt(
    invoice:
      InventoryPurchaseInvoice
  ) {
    const defaultWarehouse =
      warehouses.find(
        (row) =>
          row.is_default
      ) ??
      warehouses[0];

    const next:
      Record<
        string,
        string
      > = {};

    for (
      const item of
      invoice.purchase_invoice_items
    ) {
      next[item.id] =
        String(
          remainingPurchaseItem(
            item
          )
        );
    }

    setReceiptWarehouse(
      defaultWarehouse?.id ||
        ""
    );

    setReceiptDate(
      todayInput()
    );

    setReceiptNotes("");
    setReceiptQuantities(
      next
    );

    setMessage("");
    setSelectedInvoice(
      invoice
    );
  }

  async function saveReceipt(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !selectedInvoice ||
      !receiptWarehouse
    ) {
      return;
    }

    const items =
      selectedInvoice.purchase_invoice_items
        .map((item) => ({
          purchase_invoice_item_id:
            item.id,

          quantity:
            numeric(
              receiptQuantities[
                item.id
              ]
            ),
        }))
        .filter(
          (item) =>
            item.quantity >
            0
        );

    if (!items.length) {
      setMessage(
        "حدد كمية مستلمة."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "receive_purchase_invoice",
        {
          target_company:
            companyId,

          target_invoice:
            selectedInvoice.id,

          target_warehouse:
            receiptWarehouse,

          target_receipt_date:
            receiptDate,

          target_notes:
            receiptNotes.trim() ||
            null,

          items_payload:
            items,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setSelectedInvoice(
      null
    );

    router.refresh();
  }

  async function saveWarehouse(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !warehouseName.trim()
    ) {
      setMessage(
        "اسم المستودع مطلوب."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "create_warehouse",
        {
          target_company:
            companyId,

          target_name:
            warehouseName.trim(),

          target_code:
            warehouseCode.trim() ||
            null,

          target_address:
            warehouseAddress.trim() ||
            null,

          target_is_default:
            warehouseDefault,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setWarehouseOpen(
      false
    );

    setWarehouseName("");
    setWarehouseCode("");
    setWarehouseAddress("");
    setWarehouseDefault(
      false
    );

    router.refresh();
  }

  async function makeDefaultWarehouse(
    warehouseId: string
  ) {
    setSaving(true);

    const { error } =
      await supabase.rpc(
        "set_default_warehouse",
        {
          target_company:
            companyId,

          target_warehouse:
            warehouseId,
        }
      );

    setSaving(false);

    if (error) {
      window.alert(
        error.message
      );
      return;
    }

    router.refresh();
  }

  function openTransfer() {
    const source =
      warehouses.find(
        (row) =>
          row.is_default
      ) ??
      warehouses[0];

    const destination =
      warehouses.find(
        (row) =>
          row.id !==
          source?.id
      );

    setTransferSource(
      source?.id ||
        ""
    );

    setTransferDestination(
      destination?.id ||
        ""
    );

    setTransferDate(
      todayInput()
    );

    setTransferNotes("");

    setTransferLines([
      {
        productId: "",
        quantity: "",
      },
    ]);

    setMessage("");
    setTransferOpen(
      true
    );
  }

  async function saveTransfer(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !transferSource ||
      !transferDestination
    ) {
      setMessage(
        "اختار مستودع المصدر والوجهة."
      );
      return;
    }

    if (
      transferSource ===
      transferDestination
    ) {
      setMessage(
        "مستودع المصدر والوجهة لازم يكونوا مختلفين."
      );
      return;
    }

    const items =
      transferLines
        .map(
          (line) => ({
            product_id:
              line.productId,

            quantity:
              numeric(
                line.quantity
              ),
          })
        )
        .filter(
          (line) =>
            line.product_id &&
            line.quantity >
              0
        );

    if (!items.length) {
      setMessage(
        "أضف صنف وكمية للتحويل."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "post_inventory_transfer",
        {
          target_company:
            companyId,

          target_source_warehouse:
            transferSource,

          target_destination_warehouse:
            transferDestination,

          target_transfer_date:
            transferDate,

          target_notes:
            transferNotes.trim() ||
            null,

          items_payload:
            items,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setTransferOpen(
      false
    );

    router.refresh();
  }

  function openCount() {
    const warehouse =
      warehouses.find(
        (row) =>
          row.is_default
      ) ??
      warehouses[0];

    const warehouseId =
      warehouse?.id ||
      "";

    setCountWarehouse(
      warehouseId
    );

    setCountDate(
      todayInput()
    );

    setCountNotes("");

    setCountLines(
      products.map(
        (product) => {
          const current =
            stockFor(
              warehouseId,
              product.id
            );

          return {
            productId:
              product.id,

            countedQuantity:
              String(
                numeric(
                  current?.on_hand
                )
              ),

            unitCost:
              String(
                numeric(
                  current?.average_cost
                )
              ),
          };
        }
      )
    );

    setMessage("");
    setCountOpen(true);
  }

  function changeCountWarehouse(
    warehouseId: string
  ) {
    setCountWarehouse(
      warehouseId
    );

    setCountLines(
      products.map(
        (product) => {
          const current =
            stockFor(
              warehouseId,
              product.id
            );

          return {
            productId:
              product.id,

            countedQuantity:
              String(
                numeric(
                  current?.on_hand
                )
              ),

            unitCost:
              String(
                numeric(
                  current?.average_cost
                )
              ),
          };
        }
      )
    );
  }

  async function saveCount(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!countWarehouse) {
      setMessage(
        "اختار المستودع."
      );
      return;
    }

    const items =
      countLines.map(
        (line) => ({
          product_id:
            line.productId,

          counted_quantity:
            numeric(
              line.countedQuantity
            ),

          unit_cost:
            line.unitCost
              ? numeric(
                  line.unitCost
                )
              : null,
        })
      );

    if (!items.length) {
      setMessage(
        "ما في أصناف للجرد."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "post_inventory_count",
        {
          target_company:
            companyId,

          target_warehouse:
            countWarehouse,

          target_count_date:
            countDate,

          target_notes:
            countNotes.trim() ||
            null,

          items_payload:
            items,
        }
      );

    setSaving(false);

    if (error) {
      setMessage(
        error.message
      );
      return;
    }

    setCountOpen(false);

    router.refresh();
  }

  function inventoryDocumentStatusLabel(
    status: string
  ) {
    if (status === "posted") {
      return "?????";
    }

    if (
      status === "reversed" ||
      status === "cancelled"
    ) {
      return "?????";
    }

    return status;
  }

  async function reverseInventoryDocument(
    kind: "receipt" | "transfer" | "count",
    id: string,
    number: string
  ) {
    const label =
      kind === "receipt"
        ? "????????"
        : kind === "transfer"
          ? "???????"
          : "?????";

    const reason = window.prompt(
      `??? ??? ${label} ${number}:`
    );

    if (reason === null) return;

    if (!reason.trim()) {
      window.alert("???? ??? ?????.");
      return;
    }

    if (
      !window.confirm(
        `????? ??? ${label} ${number}? ???? ????? ???? ????? ?? ???? ????? ??????.`
      )
    ) {
      return;
    }

    const operationId =
      `${kind}:${id}`;

    setReversingId(operationId);

    try {
      let error:
        { message: string } | null =
        null;

      if (kind === "receipt") {
        const result =
          await supabase.rpc(
            "reverse_goods_receipt",
            {
              target_company: companyId,
              target_receipt: id,
              target_reason:
                reason.trim(),
            }
          );

        error = result.error;

      } else if (
        kind === "transfer"
      ) {
        const result =
          await supabase.rpc(
            "reverse_inventory_transfer",
            {
              target_company: companyId,
              target_transfer: id,
              target_reason:
                reason.trim(),
            }
          );

        error = result.error;

      } else {
        const result =
          await supabase.rpc(
            "reverse_inventory_count",
            {
              target_company: companyId,
              target_count: id,
              target_reason:
                reason.trim(),
            }
          );

        error = result.error;
      }

      if (error) {
        window.alert(error.message);
        return;
      }

      router.refresh();

    } finally {
      setReversingId(null);
    }
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Inventory Control
          </span>

          <h2>
            إدارة المخزون
          </h2>

          <p className="muted">
            المخزون الفعلي، الحجوزات، الاستلام،
            التحويل بين المستودعات والجرد.
          </p>
        </div>

        {canAdjust && (
          <div className="rowActions">
            <button
              type="button"
              className="softButton"
              onClick={() => {
                setMessage("");
                setWarehouseOpen(
                  true
                );
              }}
            >
              <Icons.plus
                size={14}
              />
              مستودع
            </button>

            <button
              type="button"
              className="softButton"
              disabled={
                warehouses.length <
                2
              }
              onClick={
                openTransfer
              }
            >
              تحويل مخزون
            </button>

            <button
              type="button"
              className="primaryButton"
              onClick={
                openCount
              }
            >
              جرد فعلي
            </button>
          </div>
        )}
      </div>

      <section className="statsGrid">
        <Mini
          title="المستودعات"
          value={String(
            warehouses.length
          )}
        />

        <Mini
          title="أصناف محجوزة"
          value={String(
            reservedLines
          )}
        />

        <Mini
          title="غير متاح"
          value={String(
            outOfStock
          )}
        />

        <Mini
          title={
            canViewCost
              ? "قيمة المخزون"
              : "بانتظار الاستلام"
          }
          value={
            canViewCost
              ? `${stockValue.toFixed(
                  2
                )} ${currency}`
              : String(
                  pendingInvoices.length
                )
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
            <h2>
              المستودعات
            </h2>

            <p>
              نقاط التخزين الفعالة بالشركة
            </p>
          </div>
        </div>

        <div className="quickList">
          {warehouses.map(
            (warehouse) => (
              <div
                className="quickItem"
                key={
                  warehouse.id
                }
              >
                <div className="quickIcon">
                  <Icons.box
                    size={15}
                  />
                </div>

                <div>
                  <strong>
                    {
                      warehouse.name
                    }
                  </strong>

                  <span>
                    {warehouse.code ||
                      "بدون كود"}
                    {warehouse.address
                      ? ` • ${warehouse.address}`
                      : ""}
                  </span>
                </div>

                {warehouse.is_default ? (
                  <span className="chip green">
                    رئيسي
                  </span>
                ) : canAdjust ? (
                  <button
                    type="button"
                    className="softButton"
                    disabled={
                      saving
                    }
                    onClick={() =>
                      void makeDefaultWarehouse(
                        warehouse.id
                      )
                    }
                  >
                    جعله رئيسي
                  </button>
                ) : null}
              </div>
            )
          )}
        </div>
      </section>

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
              placeholder="بحث بالصنف أو الكود..."
            />
          </div>

          <select
            value={
              warehouseFilter
            }
            onChange={(
              event
            ) =>
              setWarehouseFilter(
                event.target
                  .value
              )
            }
          >
            <option value="all">
              كل المستودعات
            </option>

            {warehouses.map(
              (row) => (
                <option
                  value={row.id}
                  key={row.id}
                >
                  {row.name}
                </option>
              )
            )}
          </select>

          <div />

          <div className="resultCount">
            {
              filteredStock.length
            }{" "}
            نتيجة
          </div>
        </div>

        {!filteredStock.length ? (
          <div className="empty">
            <Icons.box
              size={30}
            />

            <h3>
              ما في مخزون
            </h3>

            <p>
              أول استلام أو جرد رح يظهر هون.
            </p>
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

                  {canViewCost && (
                    <>
                      <th>
                        متوسط التكلفة
                      </th>
                      <th>
                        القيمة
                      </th>
                    </>
                  )}
                </tr>
              </thead>

              <tbody>
                {filteredStock.map(
                  (row) => (
                    <tr
                      key={`${row.warehouse_id}:${row.product_id}`}
                    >
                      <td>
                        <strong>
                          {
                            row.product_name
                          }
                        </strong>

                        <div className="muted">
                          {row.sku ||
                            "بدون كود"}
                          {row.unit
                            ? ` • ${row.unit}`
                            : ""}
                        </div>
                      </td>

                      <td>
                        {
                          row.warehouse_name
                        }
                      </td>

                      <td>
                        {numeric(
                          row.on_hand
                        ).toFixed(3)}
                      </td>

                      <td>
                        {numeric(
                          row.reserved
                        ).toFixed(3)}
                      </td>

                      <td>
                        <span
                          className={`chip ${
                            numeric(
                              row.available
                            ) > 0
                              ? "green"
                              : "gray"
                          }`}
                        >
                          {numeric(
                            row.available
                          ).toFixed(3)}
                        </span>
                      </td>

                      {canViewCost && (
                        <>
                          <td>
                            {numeric(
                              row.average_cost
                            ).toFixed(
                              4
                            )}{" "}
                            {currency}
                          </td>

                          <td>
                            {numeric(
                              row.stock_value
                            ).toFixed(
                              2
                            )}{" "}
                            {currency}
                          </td>
                        </>
                      )}
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
              مشتريات بانتظار الاستلام
            </h2>

            <p>
              الكميات المشتراة التي لم تدخل المخزن بالكامل
            </p>
          </div>
        </div>

        {!pendingInvoices.length ? (
          <p className="muted">
            ما في مشتريات معلقة.
          </p>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الفاتورة</th>
                  <th>المورد</th>
                  <th>التاريخ</th>
                  <th>المتبقي</th>
                  <th>الإجراء</th>
                </tr>
              </thead>

              <tbody>
                {pendingInvoices.map(
                  (invoice) => {
                    const supplier =
                      oneRelation(
                        invoice.suppliers
                      );

                    const remaining =
                      invoice.purchase_invoice_items.reduce(
                        (
                          sum,
                          item
                        ) =>
                          sum +
                          remainingPurchaseItem(
                            item
                          ),
                        0
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
                            "مورد"}
                        </td>

                        <td>
                          {
                            invoice.invoice_date
                          }
                        </td>

                        <td>
                          {remaining.toFixed(
                            3
                          )}
                        </td>

                        <td>
                          {canReceive && (
                            <button
                              type="button"
                              className="primaryButton"
                              onClick={() =>
                                openReceipt(
                                  invoice
                                )
                              }
                            >
                              استلام
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
        )}
      </section>

      <section
        className="panel panelPad"
        style={{ marginTop: 14 }}
      >
        <div className="panelHeader">
          <div>
            <h2>??? ??????????</h2>
            <p>
              ????? ????? ????????? ??? ???????
            </p>
          </div>
        </div>

        {!receipts.length ? (
          <p className="muted">
            ?? ?? ???????? ?????.
          </p>
        ) : (
          <div className="quickList">
            {receipts
              .slice(0, 10)
              .map((row) => {
                const operationId =
                  `receipt:${row.id}`;

                return (
                  <div
                    className="quickItem"
                    key={row.id}
                  >
                    <div>
                      <strong>
                        {row.receipt_number}
                      </strong>

                      <span>
                        {warehouseNameById(
                          row.warehouse_id
                        )}{" "}
                        ? {row.receipt_date}
                      </span>
                    </div>

                    <div className="rowActions">
                      <span
                        className={`chip ${
                          row.status === "posted"
                            ? "green"
                            : "gray"
                        }`}
                      >
                        {inventoryDocumentStatusLabel(
                          row.status
                        )}
                      </span>

                      {canReverseReceipt &&
                        row.status ===
                          "posted" && (
                          <button
                            type="button"
                            className="softButton"
                            disabled={
                              reversingId ===
                              operationId
                            }
                            onClick={() =>
                              void reverseInventoryDocument(
                                "receipt",
                                row.id,
                                row.receipt_number
                              )
                            }
                          >
                            {reversingId ===
                            operationId
                              ? "?? ????..."
                              : "??? ????????"}
                          </button>
                        )}
                    </div>
                  </div>
                );
              })}
          </div>
        )}
      </section>

      <div className="pageGrid">
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>
                آخر التحويلات
              </h2>
            </div>
          </div>

          {!transfers.length ? (
            <p className="muted">
              ما في تحويلات لسا.
            </p>
          ) : (
            <div className="quickList">
              {transfers
                .slice(0, 10)
                .map(
                  (row) => (
                    <div
                      className="quickItem"
                      key={
                        row.id
                      }
                    >
                      <div>
                        <strong>
                          {
                            row.transfer_number
                          }
                        </strong>

                        <span>
                          {warehouseNameById(
                            row.source_warehouse_id
                          )}{" "}
                          ←{" "}
                          {warehouseNameById(
                            row.destination_warehouse_id
                          )}
                        </span>
                      </div>

                      <span className="chip green">
                        مرحّل
                      </span>
                    </div>
                  )
                )}
            </div>
          )}
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>
                آخر الجرد
              </h2>
            </div>
          </div>

          {!counts.length ? (
            <p className="muted">
              ما في جرد مسجل.
            </p>
          ) : (
            <div className="quickList">
              {counts
                .slice(0, 10)
                .map(
                  (row) => (
                    <div
                      className="quickItem"
                      key={
                        row.id
                      }
                    >
                      <div>
                        <strong>
                          {
                            row.count_number
                          }
                        </strong>

                        <span>
                          {warehouseNameById(
                            row.warehouse_id
                          )}{" "}
                          •{" "}
                          {
                            row.count_date
                          }
                        </span>
                      </div>
                    </div>
                  )
                )}
            </div>
          )}
        </aside>
      </div>

      {warehouseOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  مستودع جديد
                </span>

                <h2>
                  إضافة مستودع
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={
                  saving
                }
                onClick={() =>
                  setWarehouseOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveWarehouse
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    الاسم *
                  </span>

                  <input
                    value={
                      warehouseName
                    }
                    onChange={(
                      event
                    ) =>
                      setWarehouseName(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    الكود
                  </span>

                  <input
                    value={
                      warehouseCode
                    }
                    onChange={(
                      event
                    ) =>
                      setWarehouseCode(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    العنوان
                  </span>

                  <input
                    value={
                      warehouseAddress
                    }
                    onChange={(
                      event
                    ) =>
                      setWarehouseAddress(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    نوع المستودع
                  </span>

                  <select
                    value={
                      warehouseDefault
                        ? "yes"
                        : "no"
                    }
                    onChange={(
                      event
                    ) =>
                      setWarehouseDefault(
                        event.target
                          .value ===
                          "yes"
                      )
                    }
                  >
                    <option value="no">
                      مستودع عادي
                    </option>

                    <option value="yes">
                      المستودع الرئيسي
                    </option>
                  </select>
                </label>
              </div>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setWarehouseOpen(
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
                  حفظ المستودع
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {transferOpen && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 850,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Warehouse Transfer
                </span>

                <h2>
                  تحويل مخزون
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setTransferOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveTransfer
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    من مستودع
                  </span>

                  <select
                    value={
                      transferSource
                    }
                    onChange={(
                      event
                    ) =>
                      setTransferSource(
                        event.target
                          .value
                      )
                    }
                  >
                    {warehouses.map(
                      (row) => (
                        <option
                          key={
                            row.id
                          }
                          value={
                            row.id
                          }
                        >
                          {row.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    إلى مستودع
                  </span>

                  <select
                    value={
                      transferDestination
                    }
                    onChange={(
                      event
                    ) =>
                      setTransferDestination(
                        event.target
                          .value
                      )
                    }
                  >
                    {warehouses.map(
                      (row) => (
                        <option
                          key={
                            row.id
                          }
                          value={
                            row.id
                          }
                        >
                          {row.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    التاريخ
                  </span>

                  <input
                    type="date"
                    value={
                      transferDate
                    }
                    onChange={(
                      event
                    ) =>
                      setTransferDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              <div
                className="quickList"
                style={{
                  marginTop: 14,
                }}
              >
                {transferLines.map(
                  (
                    line,
                    index
                  ) => (
                    <div
                      className="quickItem"
                      key={
                        index
                      }
                      style={{
                        display:
                          "grid",
                        gridTemplateColumns:
                          "1fr 160px auto",
                      }}
                    >
                      <label className="field">
                        <span>
                          الصنف
                        </span>

                        <select
                          value={
                            line.productId
                          }
                          onChange={(
                            event
                          ) =>
                            setTransferLines(
                              (
                                current
                              ) =>
                                current.map(
                                  (
                                    row,
                                    rowIndex
                                  ) =>
                                    rowIndex ===
                                    index
                                      ? {
                                          ...row,
                                          productId:
                                            event
                                              .target
                                              .value,
                                        }
                                      : row
                                )
                            )
                          }
                        >
                          <option value="">
                            اختار
                          </option>

                          {products.map(
                            (
                              product
                            ) => (
                              <option
                                value={
                                  product.id
                                }
                                key={
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
                      </label>

                      <label className="field">
                        <span>
                          الكمية
                        </span>

                        <input
                          type="number"
                          min="0.001"
                          step="0.001"
                          value={
                            line.quantity
                          }
                          onChange={(
                            event
                          ) =>
                            setTransferLines(
                              (
                                current
                              ) =>
                                current.map(
                                  (
                                    row,
                                    rowIndex
                                  ) =>
                                    rowIndex ===
                                    index
                                      ? {
                                          ...row,
                                          quantity:
                                            event
                                              .target
                                              .value,
                                        }
                                      : row
                                )
                            )
                          }
                        />
                      </label>

                      <button
                        type="button"
                        className="dangerButton"
                        onClick={() =>
                          setTransferLines(
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
                        ×
                      </button>
                    </div>
                  )
                )}
              </div>

              <button
                type="button"
                className="softButton"
                style={{
                  marginTop: 10,
                }}
                onClick={() =>
                  setTransferLines(
                    (
                      current
                    ) => [
                      ...current,
                      {
                        productId:
                          "",
                        quantity:
                          "",
                      },
                    ]
                  )
                }
              >
                <Icons.plus
                  size={13}
                />
                إضافة صنف
              </button>

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>
                  ملاحظات
                </span>

                <textarea
                  rows={3}
                  value={
                    transferNotes
                  }
                  onChange={(
                    event
                  ) =>
                    setTransferNotes(
                      event.target
                        .value
                    )
                  }
                />
              </label>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setTransferOpen(
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
                  ترحيل التحويل
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {countOpen && (
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
                  Stock Count
                </span>

                <h2>
                  جرد فعلي
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setCountOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveCount
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    المستودع
                  </span>

                  <select
                    value={
                      countWarehouse
                    }
                    onChange={(
                      event
                    ) =>
                      changeCountWarehouse(
                        event.target
                          .value
                      )
                    }
                  >
                    {warehouses.map(
                      (row) => (
                        <option
                          key={
                            row.id
                          }
                          value={
                            row.id
                          }
                        >
                          {row.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    التاريخ
                  </span>

                  <input
                    type="date"
                    value={
                      countDate
                    }
                    onChange={(
                      event
                    ) =>
                      setCountDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              <div
                className="tableWrap"
                style={{
                  marginTop: 15,
                }}
              >
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th>
                        الصنف
                      </th>
                      <th>
                        النظام
                      </th>
                      <th>
                        العدد الفعلي
                      </th>

                      {canViewCost && (
                        <th>
                          تكلفة
                        </th>
                      )}
                    </tr>
                  </thead>

                  <tbody>
                    {countLines.map(
                      (
                        line,
                        index
                      ) => {
                        const product =
                          products.find(
                            (
                              row
                            ) =>
                              row.id ===
                              line.productId
                          );

                        const system =
                          stockFor(
                            countWarehouse,
                            line.productId
                          );

                        return (
                          <tr
                            key={
                              line.productId
                            }
                          >
                            <td>
                              <strong>
                                {product?.name ||
                                  "صنف"}
                              </strong>
                            </td>

                            <td>
                              {numeric(
                                system?.on_hand
                              ).toFixed(
                                3
                              )}
                            </td>

                            <td>
                              <input
                                type="number"
                                min="0"
                                step="0.001"
                                value={
                                  line.countedQuantity
                                }
                                onChange={(
                                  event
                                ) =>
                                  setCountLines(
                                    (
                                      current
                                    ) =>
                                      current.map(
                                        (
                                          row,
                                          rowIndex
                                        ) =>
                                          rowIndex ===
                                          index
                                            ? {
                                                ...row,
                                                countedQuantity:
                                                  event
                                                    .target
                                                    .value,
                                              }
                                            : row
                                      )
                                  )
                                }
                              />
                            </td>

                            {canViewCost && (
                              <td>
                                <input
                                  type="number"
                                  min="0"
                                  step="0.0001"
                                  value={
                                    line.unitCost
                                  }
                                  onChange={(
                                    event
                                  ) =>
                                    setCountLines(
                                      (
                                        current
                                      ) =>
                                        current.map(
                                          (
                                            row,
                                            rowIndex
                                          ) =>
                                            rowIndex ===
                                            index
                                              ? {
                                                  ...row,
                                                  unitCost:
                                                    event
                                                      .target
                                                      .value,
                                                }
                                              : row
                                        )
                                    )
                                  }
                                />
                              </td>
                            )}
                          </tr>
                        );
                      }
                    )}
                  </tbody>
                </table>
              </div>

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>
                  ملاحظات الجرد
                </span>

                <textarea
                  rows={3}
                  value={
                    countNotes
                  }
                  onChange={(
                    event
                  ) =>
                    setCountNotes(
                      event.target
                        .value
                    )
                  }
                />
              </label>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setCountOpen(
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
                  ترحيل الجرد
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {selectedInvoice && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 850,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Goods Receipt
                </span>

                <h2>
                  استلام مشتريات
                </h2>

                <p className="muted">
                  {
                    selectedInvoice.invoice_number
                  }
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setSelectedInvoice(
                    null
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveReceipt
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    المستودع
                  </span>

                  <select
                    value={
                      receiptWarehouse
                    }
                    onChange={(
                      event
                    ) =>
                      setReceiptWarehouse(
                        event.target
                          .value
                      )
                    }
                  >
                    {warehouses.map(
                      (row) => (
                        <option
                          key={
                            row.id
                          }
                          value={
                            row.id
                          }
                        >
                          {row.name}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    التاريخ
                  </span>

                  <input
                    type="date"
                    value={
                      receiptDate
                    }
                    onChange={(
                      event
                    ) =>
                      setReceiptDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              <div
                className="quickList"
                style={{
                  marginTop: 14,
                }}
              >
                {selectedInvoice.purchase_invoice_items
                  .filter(
                    (item) =>
                      remainingPurchaseItem(
                        item
                      ) > 0
                  )
                  .map(
                    (item) => {
                      const product =
                        oneRelation(
                          item.products
                        );

                      const remaining =
                        remainingPurchaseItem(
                          item
                        );

                      return (
                        <div
                          className="quickItem"
                          key={
                            item.id
                          }
                        >
                          <div>
                            <strong>
                              {product?.name ||
                                item.description ||
                                "صنف"}
                            </strong>

                            <span>
                              باقي{" "}
                              {remaining.toFixed(
                                3
                              )}
                            </span>
                          </div>

                          <label className="field">
                            <span>
                              استلام الآن
                            </span>

                            <input
                              type="number"
                              min="0"
                              max={
                                remaining
                              }
                              step="0.001"
                              value={
                                receiptQuantities[
                                  item.id
                                ] ?? ""
                              }
                              onChange={(
                                event
                              ) =>
                                setReceiptQuantities(
                                  (
                                    current
                                  ) => ({
                                    ...current,
                                    [item.id]:
                                      event
                                        .target
                                        .value,
                                  })
                                )
                              }
                            />
                          </label>
                        </div>
                      );
                    }
                  )}
              </div>

              <label
                className="field"
                style={{
                  marginTop: 14,
                }}
              >
                <span>
                  ملاحظات
                </span>

                <textarea
                  rows={3}
                  value={
                    receiptNotes
                  }
                  onChange={(
                    event
                  ) =>
                    setReceiptNotes(
                      event.target
                        .value
                    )
                  }
                />
              </label>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setSelectedInvoice(
                      null
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
                  تأكيد الاستلام
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