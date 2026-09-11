"use client";

import Link from "next/link";
import {
  useEffect,
  useMemo,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";
import { Icons } from "@/components/icons";

type TraderRelation = {
  id: string;
  name: string;
  area: string | null;
  address: string | null;
  phone: string | null;
  whatsapp: string | null;
  latitude: number | null;
  longitude: number | null;
};

type ProductRelation = {
  name: string;
  sku: string | null;
  unit: string | null;
};

export type DeliveryOrderItem = {
  id: string;
  product_id: string;
  quantity: number;
  sale_unit_price: number;
  products:
    | ProductRelation
    | ProductRelation[]
    | null;
};

export type DeliveryOrder = {
  id: string;
  status:
    | "ready"
    | "out_for_delivery";
  payment_status:
    | "unpaid"
    | "partial"
    | "paid"
    | "credit";
  total: number;
  created_at: string;
  traders:
    | TraderRelation
    | TraderRelation[]
    | null;
  sales_order_items:
    DeliveryOrderItem[];
};

type DeliveryRelation = {
  id: string;
  order_id: string;
  status:
    | "pending"
    | "out_for_delivery"
    | "delivered"
    | "failed";
  delivery_number:
    string | null;
  created_at: string;
  delivered_at:
    string | null;
};

export type DeliveryAllocation = {
  id: string;
  sales_order_item_id: string;
  quantity: number;
  delivery_id: string;
  deliveries:
    | DeliveryRelation
    | DeliveryRelation[]
    | null;
};

function oneRelation<T>(
  value: T | T[] | null
) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

function numberValue(
  value: unknown
) {
  const result =
    Number(value || 0);

  return Number.isFinite(result)
    ? result
    : 0;
}

export function DeliveriesClient({
  companyId,
  currency,
  initialOrders,
  initialAllocations,
  canUpdate,
}: {
  companyId: string;
  currency: string;
  initialOrders: DeliveryOrder[];
  initialAllocations:
    DeliveryAllocation[];
  canUpdate: boolean;
}) {
  const [supabase] =
    useState(
      () => createClient()
    );

  const router =
    useRouter();

  const [
    rows,
    setRows,
  ] = useState(
    initialOrders
  );

  const [
    allocations,
    setAllocations,
  ] = useState(
    initialAllocations
  );

  const [
    selectedOrder,
    setSelectedOrder,
  ] =
    useState<DeliveryOrder | null>(
      null
    );

  const [
    quantities,
    setQuantities,
  ] =
    useState<
      Record<string, string>
    >({});

  const [
    busyId,
    setBusyId,
  ] =
    useState<string | null>(
      null
    );

  const [
    message,
    setMessage,
  ] =
    useState("");

  useEffect(() => {
    setRows(initialOrders);
  }, [initialOrders]);

  useEffect(() => {
    setAllocations(
      initialAllocations
    );
  }, [initialAllocations]);

  const usedByOrderItem =
    useMemo(() => {
      const map =
        new Map<
          string,
          number
        >();

      for (
        const row of
        allocations
      ) {
        const delivery =
          oneRelation(
            row.deliveries
          );

        if (
          !delivery ||
          ![
            "out_for_delivery",
            "delivered",
          ].includes(
            delivery.status
          )
        ) {
          continue;
        }

        map.set(
          row.sales_order_item_id,
          (
            map.get(
              row.sales_order_item_id
            ) || 0
          ) +
            numberValue(
              row.quantity
            )
        );
      }

      return map;
    }, [allocations]);

  function remainingQuantity(
    item: DeliveryOrderItem
  ) {
    return Math.max(
      0,
      numberValue(
        item.quantity
      ) -
        (
          usedByOrderItem.get(
            item.id
          ) || 0
        )
    );
  }

  function deliveredQuantity(
    item: DeliveryOrderItem
  ) {
    let result = 0;

    for (
      const row of
      allocations
    ) {
      if (
        row.sales_order_item_id !==
        item.id
      ) {
        continue;
      }

      const delivery =
        oneRelation(
          row.deliveries
        );

      if (
        delivery?.status ===
        "delivered"
      ) {
        result +=
          numberValue(
            row.quantity
          );
      }
    }

    return result;
  }

  function activeQuantity(
    item: DeliveryOrderItem
  ) {
    let result = 0;

    for (
      const row of
      allocations
    ) {
      if (
        row.sales_order_item_id !==
        item.id
      ) {
        continue;
      }

      const delivery =
        oneRelation(
          row.deliveries
        );

      if (
        delivery?.status ===
        "out_for_delivery"
      ) {
        result +=
          numberValue(
            row.quantity
          );
      }
    }

    return result;
  }

  function openDelivery(
    order: DeliveryOrder
  ) {
    if (!canUpdate) {
      return;
    }

    const next:
      Record<
        string,
        string
      > = {};

    for (
      const item of
      order.sales_order_items
    ) {
      const remaining =
        remainingQuantity(
          item
        );

      next[item.id] =
        remaining > 0
          ? String(remaining)
          : "0";
    }

    setQuantities(next);
    setMessage("");
    setSelectedOrder(order);
  }

  function fillAll() {
    if (!selectedOrder) {
      return;
    }

    const next:
      Record<
        string,
        string
      > = {};

    for (
      const item of
      selectedOrder.sales_order_items
    ) {
      next[item.id] =
        String(
          remainingQuantity(
            item
          )
        );
    }

    setQuantities(next);
  }

  async function saveDelivery(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !selectedOrder ||
      !canUpdate
    ) {
      return;
    }

    setMessage("");

    const payload =
      selectedOrder.sales_order_items
        .map((item) => {
          const remaining =
            remainingQuantity(
              item
            );

          const quantity =
            numberValue(
              quantities[
                item.id
              ]
            );

          return {
            sales_order_item_id:
              item.id,
            quantity,
            remaining,
          };
        })
        .filter(
          (item) =>
            item.quantity > 0
        );

    if (!payload.length) {
      setMessage(
        "حدد كمية واحدة على الأقل للتوصيل."
      );
      return;
    }

    if (
      payload.some(
        (item) =>
          item.quantity >
          item.remaining +
            0.0001
      )
    ) {
      setMessage(
        "في كمية أكبر من الكمية المتبقية."
      );
      return;
    }

    setBusyId(
      selectedOrder.id
    );

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "create_order_delivery",
        {
          target_company:
            companyId,

          target_order:
            selectedOrder.id,

          items_payload:
            payload.map(
              (item) => ({
                sales_order_item_id:
                  item.sales_order_item_id,

                quantity:
                  item.quantity,
              })
            ),
        }
      );

    setBusyId(null);

    if (error) {
      if (
        error.message.includes(
          "exceeds remaining"
        )
      ) {
        setMessage(
          "الكمية المختارة أكبر من المتبقي."
        );
      } else if (
        error.message.includes(
          "active delivery"
        )
      ) {
        setMessage(
          "في تسليمة طالعة حاليًا لهالطلبية."
        );
      } else {
        setMessage(
          error.message
        );
      }

      return;
    }

    const newDeliveryId =
      String(data);

    const selected =
      payload.map(
        (item) => ({
          id:
            crypto.randomUUID(),

          sales_order_item_id:
            item.sales_order_item_id,

          quantity:
            item.quantity,

          delivery_id:
            newDeliveryId,

          deliveries: {
            id:
              newDeliveryId,

            order_id:
              selectedOrder.id,

            status:
              "out_for_delivery" as const,

            delivery_number:
              null,

            created_at:
              new Date()
                .toISOString(),

            delivered_at:
              null,
          },
        })
      );

    setAllocations(
      (current) => [
        ...current,
        ...selected,
      ]
    );

    setRows(
      (current) =>
        current.map(
          (order) =>
            order.id ===
            selectedOrder.id
              ? {
                  ...order,
                  status:
                    "out_for_delivery",
                }
              : order
        )
    );

    setSelectedOrder(null);

    router.refresh();
  }

  async function completeDelivery(
    orderId: string
  ) {
    if (!canUpdate) {
      return;
    }

    if (
      !window.confirm(
        "تأكيد أن التسليمة وصلت للعميل؟"
      )
    ) {
      return;
    }

    setBusyId(orderId);

    const { error } =
      await supabase.rpc(
        "complete_order_delivery",
        {
          target_company:
            companyId,

          target_order:
            orderId,

          target_notes:
            null,
        }
      );

    setBusyId(null);

    if (error) {
      window.alert(
        error.message
      );
      return;
    }

    router.refresh();
  }

  const readyCount =
    rows.filter(
      (order) =>
        order.status ===
        "ready"
    ).length;

  const roadCount =
    rows.filter(
      (order) =>
        order.status ===
        "out_for_delivery"
    ).length;

  const remainingUnits =
    rows.reduce(
      (sum, order) =>
        sum +
        order.sales_order_items.reduce(
          (itemSum, item) =>
            itemSum +
            remainingQuantity(
              item
            ),
          0
        ),
      0
    );

  const roadUnits =
    rows.reduce(
      (sum, order) =>
        sum +
        order.sales_order_items.reduce(
          (itemSum, item) =>
            itemSum +
            activeQuantity(
              item
            ),
          0
        ),
      0
    );

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            دورة التوصيل
          </span>

          <h2>
            تجهيز وتسليم الطلبات
          </h2>

          <p className="muted">
            فيك تسلّم الطلبية كاملة أو جزء منها،
            وكل تسليمة بتطلع لحالها وبتتحول
            لفاتورة بيع مستقلة بعد تأكيد الوصول.
          </p>
        </div>

        <Link
          href="/map"
          className="softButton"
        >
          <Icons.map size={14} />
          خريطة العملاء
        </Link>
      </div>

      <section className="statsGrid">
        <Mini
          title="جاهزة للتوصيل"
          value={String(
            readyCount
          )}
        />

        <Mini
          title="بالطريق"
          value={String(
            roadCount
          )}
        />

        <Mini
          title="قطع بالسيارة"
          value={
            roadUnits.toFixed(
              3
            )
          }
        />

        <Mini
          title="قطع متبقية"
          value={
            remainingUnits.toFixed(
              3
            )
          }
        />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        {!rows.length ? (
          <div className="empty">
            <Icons.truck
              size={30}
            />

            <h3>
              ما في طلبات للتوصيل
            </h3>

            <p>
              الطلبات الجاهزة رح تظهر هون تلقائيًا.
            </p>
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
                {rows.map(
                  (order) => {
                    const trader =
                      oneRelation(
                        order.traders
                      );

                    const totalQty =
                      order.sales_order_items.reduce(
                        (
                          sum,
                          item
                        ) =>
                          sum +
                          numberValue(
                            item.quantity
                          ),
                        0
                      );

                    const deliveredQty =
                      order.sales_order_items.reduce(
                        (
                          sum,
                          item
                        ) =>
                          sum +
                          deliveredQuantity(
                            item
                          ),
                        0
                      );

                    const activeQty =
                      order.sales_order_items.reduce(
                        (
                          sum,
                          item
                        ) =>
                          sum +
                          activeQuantity(
                            item
                          ),
                        0
                      );

                    return (
                      <tr
                        key={
                          order.id
                        }
                      >
                        <td>
                          <div className="merchant">
                            <div className="merchantLogo">
                              {trader?.name?.charAt(
                                0
                              ) ||
                                "؟"}
                            </div>

                            <div>
                              <strong>
                                {trader?.name ||
                                  "عميل"}
                              </strong>

                              <span>
                                {trader?.area ||
                                  trader?.address ||
                                  "—"}
                              </span>
                            </div>
                          </div>
                        </td>

                        <td>
                          <strong>
                            #
                            {order.id.slice(
                              0,
                              8
                            )}
                          </strong>

                          <div className="muted">
                            {
                              order
                                .sales_order_items
                                .length
                            }{" "}
                            أصناف
                          </div>
                        </td>

                        <td>
                          <strong>
                            {deliveredQty.toFixed(
                              3
                            )}{" "}
                            /{" "}
                            {totalQty.toFixed(
                              3
                            )}
                          </strong>

                          {activeQty >
                            0 && (
                            <div className="muted">
                              {activeQty.toFixed(
                                3
                              )}{" "}
                              بالطريق
                            </div>
                          )}
                        </td>

                        <td>
                          {numberValue(
                            order.total
                          ).toFixed(
                            2
                          )}{" "}
                          {currency}
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              order.status ===
                              "ready"
                                ? "orange"
                                : "blue"
                            }`}
                          >
                            {order.status ===
                            "ready"
                              ? "جاهز"
                              : "بالطريق"}
                          </span>
                        </td>

                        <td>
                          <div className="rowActions">
                            {trader?.phone && (
                              <a
                                className="softButton"
                                href={`tel:${trader.phone}`}
                              >
                                <Icons.phone
                                  size={13}
                                />
                              </a>
                            )}

                            {trader?.whatsapp && (
                              <a
                                className="softButton"
                                target="_blank"
                                rel="noreferrer"
                                href={`https://wa.me/${String(
                                  trader.whatsapp
                                ).replace(
                                  /\D/g,
                                  ""
                                )}`}
                              >
                                <Icons.whatsapp
                                  size={13}
                                />
                              </a>
                            )}

                            {trader?.latitude !=
                              null &&
                              trader?.longitude !=
                                null && (
                                <Link
                                  className="softButton"
                                  href={`/map?trader=${trader.id}`}
                                >
                                  <Icons.map
                                    size={13}
                                  />
                                </Link>
                              )}
                          </div>
                        </td>

                        <td>
                          {canUpdate ? (
                            <div className="rowActions">
                              {order.status ===
                                "ready" && (
                                <button
                                  type="button"
                                  className="primaryButton"
                                  onClick={() =>
                                    openDelivery(
                                      order
                                    )
                                  }
                                >
                                  <Icons.truck
                                    size={14}
                                  />
                                  تجهيز تسليمة
                                </button>
                              )}

                              {order.status ===
                                "out_for_delivery" && (
                                <button
                                  type="button"
                                  className="primaryButton"
                                  disabled={
                                    busyId ===
                                    order.id
                                  }
                                  onClick={() =>
                                    void completeDelivery(
                                      order.id
                                    )
                                  }
                                >
                                  {busyId ===
                                  order.id
                                    ? "عم نثبت..."
                                    : "تم التسليم"}
                                </button>
                              )}
                            </div>
                          ) : (
                            <span className="muted">
                              عرض فقط
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

      {selectedOrder && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 820,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  تسليمة جديدة
                </span>

                <h2>
                  حدد الكميات يلي رح تطلع
                </h2>

                <p className="muted">
                  طلب #
                  {selectedOrder.id.slice(
                    0,
                    8
                  )}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                disabled={
                  busyId ===
                  selectedOrder.id
                }
                onClick={() =>
                  setSelectedOrder(
                    null
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveDelivery
              }
            >
              <div className="quickList">
                {selectedOrder.sales_order_items.map(
                  (item) => {
                    const product =
                      oneRelation(
                        item.products
                      );

                    const ordered =
                      numberValue(
                        item.quantity
                      );

                    const delivered =
                      deliveredQuantity(
                        item
                      );

                    const remaining =
                      remainingQuantity(
                        item
                      );

                    return (
                      <div
                        className="quickItem"
                        key={item.id}
                        style={{
                          display:
                            "grid",
                          gridTemplateColumns:
                            "minmax(180px,1fr) 100px 100px 150px",
                          alignItems:
                            "end",
                          gap: 10,
                        }}
                      >
                        <div>
                          <strong>
                            {product?.name ||
                              "صنف"}
                          </strong>

                          <span>
                            {product?.sku ||
                              product?.unit ||
                              ""}
                          </span>
                        </div>

                        <div>
                          <span className="muted">
                            المطلوب
                          </span>

                          <strong>
                            {ordered.toFixed(
                              3
                            )}
                          </strong>
                        </div>

                        <div>
                          <span className="muted">
                            وصل
                          </span>

                          <strong>
                            {delivered.toFixed(
                              3
                            )}
                          </strong>
                        </div>

                        <label className="field">
                          <span>
                            هالتسليمة
                          </span>

                          <input
                            type="number"
                            min="0"
                            max={
                              remaining
                            }
                            step="0.001"
                            value={
                              quantities[
                                item.id
                              ] ?? ""
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
                                    event
                                      .target
                                      .value,
                                })
                              )
                            }
                          />

                          <small className="helpText">
                            باقي{" "}
                            {remaining.toFixed(
                              3
                            )}
                          </small>
                        </label>
                      </div>
                    );
                  }
                )}
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
                  disabled={
                    busyId ===
                    selectedOrder.id
                  }
                  onClick={
                    fillAll
                  }
                >
                  كل الكمية المتبقية
                </button>

                <button
                  type="button"
                  className="softButton"
                  disabled={
                    busyId ===
                    selectedOrder.id
                  }
                  onClick={() =>
                    setSelectedOrder(
                      null
                    )
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    busyId ===
                    selectedOrder.id
                  }
                >
                  {busyId ===
                  selectedOrder.id
                    ? "عم نحفظ..."
                    : "إخراج للتوصيل"}
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