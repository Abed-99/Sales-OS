"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Warehouse = {
  id: string;
  name: string;
};

type Receipt = {
  id: string;
  receipt_number: string;
  warehouse_id: string;
  status: string;
  receipt_date: string;
};

type Transfer = {
  id: string;
  transfer_number: string;
  source_warehouse_id: string;
  destination_warehouse_id: string;
  status: string;
  transfer_date: string;
};

type Count = {
  id: string;
  count_number: string;
  warehouse_id: string;
  status: string;
  count_date: string;
};

export function InventoryReversalPanel({
  companyId,
  warehouses,
  receipts,
  transfers,
  counts,
  canReverseReceipt,
  canAdjust,
}: {
  companyId: string;
  warehouses: Warehouse[];
  receipts: Receipt[];
  transfers: Transfer[];
  counts: Count[];
  canReverseReceipt: boolean;
  canAdjust: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const [busyId, setBusyId] = useState<string | null>(null);
  const router = useRouter();

  const warehouseName = (id: string) =>
    warehouses.find((row) => row.id === id)?.name || "مستودع";

  const statusLabel = (status: string) =>
    status === "posted"
      ? "مرحّل"
      : status === "reversed"
        ? "معكوس"
        : status === "cancelled"
          ? "ملغى"
          : status;

  async function reverse(
    kind: "receipt" | "transfer" | "count",
    id: string,
    number: string
  ) {
    const label =
      kind === "receipt"
        ? "الاستلام"
        : kind === "transfer"
          ? "التحويل"
          : "الجرد";

    const reason = window.prompt(
      `سبب عكس ${label} ${number}:`
    );

    if (reason === null) return;

    if (!reason.trim()) {
      window.alert("اكتب سبب العكس.");
      return;
    }

    if (
      !window.confirm(
        `تأكيد عكس ${label} ${number}؟ سيتم تسجيل حركة عكسية ولن يتم حذف السجل الأصلي.`
      )
    ) {
      return;
    }

    const operationId = `${kind}:${id}`;

    setBusyId(operationId);

    const functionName =
      kind === "receipt"
        ? "reverse_goods_receipt"
        : kind === "transfer"
          ? "reverse_inventory_transfer"
          : "reverse_inventory_count";

    const args =
      kind === "receipt"
        ? {
            target_company: companyId,
            target_receipt: id,
            target_reason: reason.trim(),
          }
        : kind === "transfer"
          ? {
              target_company: companyId,
              target_transfer: id,
              target_reason: reason.trim(),
            }
          : {
              target_company: companyId,
              target_count: id,
              target_reason: reason.trim(),
            };

    const { error } =
      await supabase.rpc(
        functionName,
        args
      );

    setBusyId(null);

    if (error) {
      window.alert(error.message);
      return;
    }

    router.refresh();
  }

  if (
    !receipts.length &&
    !transfers.length &&
    !counts.length
  ) {
    return null;
  }

  return (
    <section
      className="panel panelPad"
      style={{ marginTop: 14 }}
    >
      <div className="panelHeader">
        <div>
          <h2>عكس حركات المخزون</h2>
          <p>
            الاستلامات والتحويلات وعمليات الجرد
          </p>
        </div>
      </div>

      <div className="quickList">
        {receipts
          .slice(0, 10)
          .map((row) => {
            const key =
              `receipt:${row.id}`;

            return (
              <div
                className="quickItem"
                key={key}
              >
                <div>
                  <strong>
                    استلام {row.receipt_number}
                  </strong>

                  <span>
                    {warehouseName(
                      row.warehouse_id
                    )}{" "}
                    • {row.receipt_date}
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
                    {statusLabel(row.status)}
                  </span>

                  {canReverseReceipt &&
                  row.status === "posted" ? (
                    <button
                      type="button"
                      className="softButton"
                      disabled={
                        busyId === key
                      }
                      onClick={() =>
                        void reverse(
                          "receipt",
                          row.id,
                          row.receipt_number
                        )
                      }
                    >
                      {busyId === key
                        ? "عم نعكس..."
                        : "عكس الاستلام"}
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}

        {transfers
          .slice(0, 10)
          .map((row) => {
            const key =
              `transfer:${row.id}`;

            return (
              <div
                className="quickItem"
                key={key}
              >
                <div>
                  <strong>
                    تحويل {row.transfer_number}
                  </strong>

                  <span>
                    {warehouseName(
                      row.source_warehouse_id
                    )}{" "}
                    ←{" "}
                    {warehouseName(
                      row.destination_warehouse_id
                    )}{" "}
                    • {row.transfer_date}
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
                    {statusLabel(row.status)}
                  </span>

                  {canAdjust &&
                  row.status === "posted" ? (
                    <button
                      type="button"
                      className="softButton"
                      disabled={
                        busyId === key
                      }
                      onClick={() =>
                        void reverse(
                          "transfer",
                          row.id,
                          row.transfer_number
                        )
                      }
                    >
                      {busyId === key
                        ? "عم نعكس..."
                        : "عكس التحويل"}
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}

        {counts
          .slice(0, 10)
          .map((row) => {
            const key =
              `count:${row.id}`;

            return (
              <div
                className="quickItem"
                key={key}
              >
                <div>
                  <strong>
                    جرد {row.count_number}
                  </strong>

                  <span>
                    {warehouseName(
                      row.warehouse_id
                    )}{" "}
                    • {row.count_date}
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
                    {statusLabel(row.status)}
                  </span>

                  {canAdjust &&
                  row.status === "posted" ? (
                    <button
                      type="button"
                      className="softButton"
                      disabled={
                        busyId === key
                      }
                      onClick={() =>
                        void reverse(
                          "count",
                          row.id,
                          row.count_number
                        )
                      }
                    >
                      {busyId === key
                        ? "عم نعكس..."
                        : "عكس الجرد"}
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}
      </div>
    </section>
  );
}