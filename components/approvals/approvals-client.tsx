"use client";

import {
  useMemo,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type ApprovalRequest = {
  id: string;
  request_type: string;
  reference_type: string | null;
  reference_id: string | null;
  title: string;
  description: string | null;
  payload: Record<string, unknown>;
  status:
    | "pending"
    | "approved"
    | "rejected"
    | "cancelled";
  requested_at: string;
  resolved_at: string | null;
  resolution_notes: string | null;
  requested_by: string | null;
  resolved_by: string | null;
  created_at: string;
};

type Filter =
  | "all"
  | "pending"
  | "approved"
  | "rejected";

export function ApprovalsClient({
  companyId,
  requests,
  canResolve,
}: {
  companyId: string;
  requests: ApprovalRequest[];
  canResolve: boolean;
}) {
  const [supabase] =
    useState(() => createClient());

  const router = useRouter();

  const [filter, setFilter] =
    useState<Filter>("pending");

  const [selected, setSelected] =
    useState<ApprovalRequest | null>(null);

  const [notes, setNotes] =
    useState("");

  const [saving, setSaving] =
    useState(false);

  const [message, setMessage] =
    useState("");

  const filtered = useMemo(() => {
    if (filter === "all") {
      return requests;
    }

    return requests.filter(
      (request) =>
        request.status === filter
    );
  }, [requests, filter]);

  const pending =
    requests.filter(
      (request) =>
        request.status ===
        "pending"
    ).length;

  const approved =
    requests.filter(
      (request) =>
        request.status ===
        "approved"
    ).length;

  const rejected =
    requests.filter(
      (request) =>
        request.status ===
        "rejected"
    ).length;

  async function resolve(
    decision:
      | "approved"
      | "rejected"
  ) {
    if (!selected) {
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "resolve_approval_request",
        {
          target_company:
            companyId,

          target_request:
            selected.id,

          target_decision:
            decision,

          target_notes:
            notes.trim() ||
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

    setSelected(null);
    setNotes("");

    router.refresh();
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Approval Center
          </span>

          <h2>
            مركز الموافقات
          </h2>

          <p className="muted">
            أي عملية حساسة تحتاج اعتماد تظهر هون.
          </p>
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="بانتظار الموافقة"
          value={String(
            pending
          )}
        />

        <Mini
          title="تمت الموافقة"
          value={String(
            approved
          )}
        />

        <Mini
          title="مرفوض"
          value={String(
            rejected
          )}
        />

        <Mini
          title="إجمالي الطلبات"
          value={String(
            requests.length
          )}
        />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        <FilterButton
          active={
            filter === "pending"
          }
          onClick={() =>
            setFilter(
              "pending"
            )
          }
        >
          معلقة
        </FilterButton>

        <FilterButton
          active={
            filter === "approved"
          }
          onClick={() =>
            setFilter(
              "approved"
            )
          }
        >
          مقبولة
        </FilterButton>

        <FilterButton
          active={
            filter === "rejected"
          }
          onClick={() =>
            setFilter(
              "rejected"
            )
          }
        >
          مرفوضة
        </FilterButton>

        <FilterButton
          active={
            filter === "all"
          }
          onClick={() =>
            setFilter(
              "all"
            )
          }
        >
          الكل
        </FilterButton>
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

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        {!filtered.length ? (
          <div className="empty">
            <Icons.check
              size={30}
            />

            <h3>
              ما في طلبات هون
            </h3>

            <p>
              ما في موافقات مطابقة للحالة المختارة.
            </p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الطلب</th>
                  <th>النوع</th>
                  <th>المرجع</th>
                  <th>التاريخ</th>
                  <th>الحالة</th>
                  <th />
                </tr>
              </thead>

              <tbody>
                {filtered.map(
                  (request) => (
                    <tr
                      key={
                        request.id
                      }
                    >
                      <td>
                        <strong>
                          {
                            request.title
                          }
                        </strong>

                        <div className="muted">
                          {request.description ||
                            "بدون شرح"}
                        </div>
                      </td>

                      <td>
                        {typeLabel(
                          request.request_type
                        )}
                      </td>

                      <td>
                        {request.reference_type ||
                          "—"}
                      </td>

                      <td>
                        {new Date(
                          request.requested_at
                        ).toLocaleDateString(
                          "ar"
                        )}
                      </td>

                      <td>
                        <span
                          className={`chip ${
                            request.status ===
                            "pending"
                              ? "orange"
                              : request.status ===
                                "approved"
                              ? "green"
                              : "gray"
                          }`}
                        >
                          {statusLabel(
                            request.status
                          )}
                        </span>
                      </td>

                      <td>
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => {
                            setSelected(
                              request
                            );

                            setNotes(
                              request.resolution_notes ||
                                ""
                            );

                            setMessage(
                              ""
                            );
                          }}
                        >
                          عرض
                        </button>
                      </td>
                    </tr>
                  )
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {selected && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Approval Request
                </span>

                <h2>
                  {selected.title}
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setSelected(
                    null
                  )
                }
              >
                ×
              </button>
            </div>

            <div className="formGrid">
              <Info
                label="النوع"
                value={typeLabel(
                  selected.request_type
                )}
              />

              <Info
                label="الحالة"
                value={statusLabel(
                  selected.status
                )}
              />

              <Info
                label="المرجع"
                value={
                  selected.reference_type ||
                  "—"
                }
              />

              <Info
                label="تاريخ الطلب"
                value={new Date(
                  selected.requested_at
                ).toLocaleString(
                  "ar"
                )}
              />
            </div>

            {selected.description && (
              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                }}
              >
                {
                  selected.description
                }
              </div>
            )}

            {Object.keys(
              selected.payload ||
                {}
            ).length > 0 && (
              <div
                className="panel panelPad"
                style={{
                  marginTop: 14,
                  overflowWrap:
                    "anywhere",
                }}
              >
                <strong>
                  تفاصيل العملية
                </strong>

                <pre
                  style={{
                    whiteSpace:
                      "pre-wrap",
                    marginBottom: 0,
                  }}
                >
                  {JSON.stringify(
                    selected.payload,
                    null,
                    2
                  )}
                </pre>
              </div>
            )}

            {selected.status ===
              "pending" &&
              canResolve && (
                <label
                  className="field"
                  style={{
                    marginTop: 14,
                  }}
                >
                  <span>
                    ملاحظات القرار
                  </span>

                  <textarea
                    rows={3}
                    value={notes}
                    onChange={(
                      event
                    ) =>
                      setNotes(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              )}

            {selected.resolution_notes &&
              selected.status !==
                "pending" && (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 14,
                  }}
                >
                  <strong>
                    ملاحظات القرار
                  </strong>

                  <p>
                    {
                      selected.resolution_notes
                    }
                  </p>
                </div>
              )}

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
                  setSelected(
                    null
                  )
                }
              >
                إغلاق
              </button>

              {selected.status ===
                "pending" &&
                canResolve && (
                  <>
                    <button
                      type="button"
                      className="dangerButton"
                      disabled={saving}
                      onClick={() =>
                        void resolve(
                          "rejected"
                        )
                      }
                    >
                      رفض
                    </button>

                    <button
                      type="button"
                      className="primaryButton"
                      disabled={saving}
                      onClick={() =>
                        void resolve(
                          "approved"
                        )
                      }
                    >
                      موافقة
                    </button>
                  </>
                )}
            </div>
          </section>
        </div>
      )}
    </div>
  );
}

function FilterButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      className={
        active
          ? "primaryButton"
          : "softButton"
      }
      onClick={onClick}
    >
      {children}
    </button>
  );
}

function Info({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="field">
      <span>{label}</span>
      <strong>{value}</strong>
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

function statusLabel(
  status: ApprovalRequest["status"]
) {
  if (status === "pending") {
    return "بانتظار الموافقة";
  }

  if (status === "approved") {
    return "موافق عليه";
  }

  if (status === "rejected") {
    return "مرفوض";
  }

  return "ملغى";
}

function typeLabel(
  type: string
) {
  const labels: Record<
    string,
    string
  > = {
    discount:
      "خصم استثنائي",
    below_cost_sale:
      "بيع تحت التكلفة",
    below_cost_order:
      "طلب بيع تحت التكلفة",
    inventory_adjustment:
      "تسوية مخزون",
    expense:
      "مصروف",
    purchase:
      "شراء",
    payment:
      "دفعة",
    manual_journal:
      "قيد يدوي",
  };

  return labels[type] || type;
}