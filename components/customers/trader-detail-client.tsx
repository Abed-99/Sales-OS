"use client";

import Link from "next/link";
import {
  useState,
} from "react";
import type {
  FormEvent,
} from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type TraderDetailRow = {
  id: string;
  name: string;
  contact_name: string | null;
  phone: string | null;
  whatsapp: string | null;
  area: string | null;
  address: string | null;
  latitude:
    | number
    | string
    | null;
  longitude:
    | number
    | string
    | null;
  status: string;
  notes: string | null;
  whatsapp_marketing_opt_in: boolean;
  credit_limit: number | null;
  payment_terms_days: number;
  created_at: string;
  updated_at: string;
};

export type TraderVisitRow = {
  id: string;
  result: string;
  notes: string | null;
  contacted_at: string;
  next_follow_up_at:
    | string
    | null;
};

export type TraderOrderRow = {
  id: string;
  status: string;
  total: number;
  created_at: string;
};

export type TraderSalesSummary = {
  invoice_count: number;
  total_invoiced: number;
  outstanding: number;
  currency: string;
};

const traderStatusLabels:
  Record<string, string> = {
  new: "جديد",
  contacted: "تم التواصل",
  interested: "مهتم",
  customer: "عميل",
  inactive: "مؤرشف",
};

const orderStatusLabels:
  Record<string, string> = {
  draft: "مسودة",
  new: "جديد",
  to_purchase:
    "بانتظار التوفير",
  purchasing:
    "قيد التوفير",
  ready: "جاهز",
  out_for_delivery:
    "قيد التوصيل",
  delivered:
    "تم التسليم",
  cancelled: "ملغي",
};

function formatDamascusDateTime(
  value: string
) {
  return new Date(
    value
  ).toLocaleString(
    "ar-SY",
    {
      timeZone:
        "Asia/Damascus",
    }
  );
}

function formatDamascusDate(
  value: string
) {
  return new Date(
    value
  ).toLocaleDateString(
    "ar-SY",
    {
      timeZone:
        "Asia/Damascus",
    }
  );
}

function damascusLocalToIso(
  value: string
) {
  if (!value) {
    return null;
  }

  const normalized =
    value.length === 16
      ? `${value}:00`
      : value;

  const date =
    new Date(
      `${normalized}+03:00`
    );

  if (
    Number.isNaN(
      date.getTime()
    )
  ) {
    return null;
  }

  return date.toISOString();
}

function friendlyVisitError(
  error:
    | {
        code?: string;
        message?: string;
      }
    | null
) {
  const message =
    error?.message?.toLowerCase() ??
    "";

  if (
    error?.code === "42501" ||
    message.includes(
      "not allowed"
    ) ||
    message.includes(
      "permission"
    )
  ) {
    return "ما عندك صلاحية تسجيل هذا التواصل.";
  }

  return "تعذر حفظ التواصل. حاول مرة ثانية.";
}

export function TraderDetailClient({
  companyId,
  currency,
  trader,
  initialVisits,
  visitCount,
  orders,
  orderCount,
  salesSummary,
  canViewVisits,
  canCreateVisit,
  canViewOrders,
  canViewFinancials,
  canViewBalance,
  canViewMap,
  initialError,
}: {
  companyId: string;
  currency: string;
  trader: TraderDetailRow;
  initialVisits: TraderVisitRow[];
  visitCount: number;
  orders: TraderOrderRow[];
  orderCount: number;
  salesSummary:
    | TraderSalesSummary
    | null;
  canViewVisits: boolean;
  canCreateVisit: boolean;
  canViewOrders: boolean;
  canViewFinancials: boolean;
  canViewBalance: boolean;
  canViewMap: boolean;
  initialError:
    | string
    | null;
}) {
  const [supabase] =
    useState(() => createClient());

  const router =
    useRouter();

  const [
    visits,
    setVisits,
  ] = useState(
    initialVisits
  );

  const [
    currentVisitCount,
    setCurrentVisitCount,
  ] = useState(
    visitCount
  );

  const [open, setOpen] =
    useState(false);

  const [result, setResult] =
    useState("زيارة");

  const [notes, setNotes] =
    useState("");

  const [follow, setFollow] =
    useState("");

  const [saving, setSaving] =
    useState(false);

  const [
    message,
    setMessage,
  ] = useState("");

  function formatMoney(
    value: number,
    moneyCurrency:
      string = currency
  ) {
    return `${new Intl.NumberFormat(
      "en-US",
      {
        maximumFractionDigits:
          2,
        minimumFractionDigits:
          2,
      }
    ).format(value)} ${moneyCurrency}`;
  }

  async function save(
    event: FormEvent
  ) {
    event.preventDefault();
    setMessage("");

    if (!canCreateVisit) {
      setMessage(
        "ما عندك صلاحية تسجيل تواصل."
      );
      return;
    }

    const cleanResult =
      result.trim();

    if (!cleanResult) {
      setMessage(
        "نتيجة التواصل مطلوبة."
      );
      return;
    }

    let followIso:
      | string
      | null = null;

    if (follow) {
      followIso =
        damascusLocalToIso(
          follow
        );

      if (!followIso) {
        setMessage(
          "موعد المتابعة غير صحيح."
        );
        return;
      }
    }

    setSaving(true);

    try {
      const {
        data,
        error,
      } = await supabase
        .from(
          "trader_visits"
        )
        .insert({
          company_id:
            companyId,

          trader_id:
            trader.id,

          result:
            cleanResult,

          notes:
            notes.trim() ||
            null,

          contacted_at:
            new Date().toISOString(),

          next_follow_up_at:
            followIso,
        })
        .select(
          "id,result,notes,contacted_at,next_follow_up_at"
        )
        .single();

      if (error) {
        setMessage(
          friendlyVisitError(
            error
          )
        );
        return;
      }

      if (
        canViewVisits &&
        data
      ) {
        setVisits(
          (current) => [
            data as TraderVisitRow,
            ...current,
          ].slice(0, 100)
        );

        setCurrentVisitCount(
          (current) =>
            current + 1
        );
      }

      setOpen(false);
      setNotes("");
      setFollow("");
      setResult("زيارة");
      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="page">
      {initialError ? (
        <div
          className="toastError"
          role="alert"
          aria-live="polite"
          style={{
            marginBottom: 14,
          }}
        >
          {initialError}
        </div>
      ) : null}

      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            ملف العميل
          </span>

          <h2>
            {trader.name}
          </h2>

          <p className="muted">
            {trader.area ||
              "بدون منطقة"}

            {trader.contact_name
              ? ` • ${trader.contact_name}`
              : ""}
          </p>
        </div>

        <div className="rowActions">
          {trader.phone ? (
            <a
              className="softButton"
              href={`tel:${trader.phone}`}
            >
              <Icons.phone
                size={14}
              />
              اتصال
            </a>
          ) : null}

          {trader.whatsapp ? (
            <a
              className="primaryButton"
              target="_blank"
              rel="noreferrer"
              href={`https://wa.me/${trader.whatsapp.replace(
                /\D/g,
                ""
              )}`}
            >
              <Icons.whatsapp
                size={14}
              />
              واتساب
            </a>
          ) : null}
        </div>
      </div>

      <section className="statsGrid">
        {canViewVisits ? (
          <Mini
            t="عدد الزيارات"
            v={String(
              currentVisitCount
            )}
          />
        ) : null}

        {canViewOrders ? (
          <Mini
            t="الطلبات"
            v={String(
              orderCount
            )}
          />
        ) : null}

        {canViewFinancials ? (
          <Mini
            t={
              salesSummary
                ? `إجمالي الفواتير (${salesSummary.invoice_count})`
                : "إجمالي الفواتير"
            }
            v={
              salesSummary
                ? formatMoney(
                    salesSummary.total_invoiced,
                    salesSummary.currency
                  )
                : "—"
            }
          />
        ) : null}

        <Mini
          t="حملات واتساب"
          v={
            trader.whatsapp_marketing_opt_in
              ? "موافق"
              : "غير موافق"
          }
        />
      </section>

      <div className="pageGrid">
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>
                سجل الزيارات والمتابعات
              </h2>

              <p>
                كل تواصل مع العميل في مكان واحد
              </p>
            </div>

            {canCreateVisit ? (
              <button
                type="button"
                className="primaryButton"
                onClick={() => {
                  setMessage("");
                  setOpen(true);
                }}
              >
                <Icons.plus
                  size={14}
                />
                سجل تواصل
              </button>
            ) : null}
          </div>

          {!canViewVisits ? (
            <div className="empty">
              <Icons.shield
                size={28}
              />

              <h3>
                لا تملك صلاحية عرض سجل الزيارات
              </h3>
            </div>
          ) : !visits.length ? (
            <div className="empty">
              <Icons.calendar
                size={28}
              />

              <h3>
                لا توجد زيارات مسجلة
              </h3>

              <p>
                سجل أول زيارة أو اتصال.
              </p>
            </div>
          ) : (
            <>
              {currentVisitCount >
              visits.length ? (
                <p className="muted">
                  يعرض أحدث{" "}
                  {visits.length} من{" "}
                  {currentVisitCount} سجل.
                </p>
              ) : null}

              <div className="quickList">
                {visits.map(
                  (visit) => (
                    <div
                      className="quickItem"
                      key={
                        visit.id
                      }
                    >
                      <div className="quickIcon">
                        <Icons.calendar
                          size={
                            16
                          }
                        />
                      </div>

                      <div>
                        <strong>
                          {
                            visit.result
                          }
                        </strong>

                        <span>
                          {visit.notes ||
                            "بدون ملاحظات"}
                          {" • "}
                          {formatDamascusDateTime(
                            visit.contacted_at
                          )}
                        </span>
                      </div>

                      <div className="count">
                        {visit.next_follow_up_at
                          ? `متابعة ${formatDamascusDate(
                              visit.next_follow_up_at
                            )}`
                          : "تم"}
                      </div>
                    </div>
                  )
                )}
              </div>
            </>
          )}
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>
                معلومات العميل
              </h2>

              <p>
                البيانات الأساسية
              </p>
            </div>
          </div>

          <div className="quickList">
            <Info
              t="الهاتف"
              v={
                trader.phone ||
                "—"
              }
            />

            <Info
              t="واتساب"
              v={
                trader.whatsapp ||
                "—"
              }
            />

            <Info
              t="العنوان"
              v={
                trader.address ||
                "—"
              }
            />

            <Info
              t="الحالة"
              v={
                traderStatusLabels[
                  trader.status
                ] ||
                "غير معروف"
              }
            />

            {canViewBalance ? (
              <>
                <Info
                  t="حد الائتمان"
                  v={
                    trader.credit_limit ==
                    null
                      ? "بدون حد"
                      : formatMoney(
                          Number(
                            trader.credit_limit
                          )
                        )
                  }
                />

                <Info
                  t="مهلة الدفع"
                  v={
                    trader.payment_terms_days >
                    0
                      ? `${trader.payment_terms_days} يوم`
                      : "نقدي"
                  }
                />
              </>
            ) : null}

            {canViewFinancials &&
            salesSummary ? (
              <Info
                t="الرصيد المستحق"
                v={formatMoney(
                  salesSummary.outstanding,
                  salesSummary.currency
                )}
              />
            ) : null}

            {trader.notes ? (
              <Info
                t="ملاحظات"
                v={
                  trader.notes
                }
              />
            ) : null}

            {canViewMap &&
            trader.latitude !=
              null &&
            trader.longitude !=
              null ? (
              <Link
                className="softButton"
                href={`/map?trader=${trader.id}`}
              >
                <Icons.map
                  size={14}
                />
                فتح على الخريطة
              </Link>
            ) : null}
          </div>

          {canViewOrders ? (
            <>
              <div
                className="panelHeader"
                style={{
                  marginTop: 20,
                }}
              >
                <div>
                  <h2>
                    آخر الطلبات
                  </h2>

                  <p>
                    أحدث الطلبات غير الملغاة
                  </p>
                </div>
              </div>

              {!orders.length ? (
                <p className="muted">
                  لا توجد طلبات.
                </p>
              ) : (
                <div className="quickList">
                  {orders.map(
                    (order) => (
                      <Link
                        key={
                          order.id
                        }
                        href={`/orders?order=${order.id}`}
                        className="quickItem"
                        style={{
                          textDecoration:
                            "none",
                        }}
                      >
                        <div className="quickIcon">
                          <Icons.cart
                            size={
                              15
                            }
                          />
                        </div>

                        <div>
                          <strong>
                            طلب{" "}
                            {order.id.slice(
                              0,
                              8
                            )}
                          </strong>

                          <span>
                            {orderStatusLabels[
                              order
                                .status
                            ] ||
                              "غير معروف"}
                            {" • "}
                            {formatDamascusDate(
                              order.created_at
                            )}
                          </span>
                        </div>

                        <div className="count">
                          {formatMoney(
                            Number(
                              order.total
                            )
                          )}
                        </div>
                      </Link>
                    )
                  )}
                </div>
              )}
            </>
          ) : null}
        </aside>
      </div>

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
            role="dialog"
            aria-modal="true"
            aria-labelledby="visit-modal-title"
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  متابعة جديدة
                </span>

                <h2 id="visit-modal-title">
                  تسجيل تواصل مع{" "}
                  {trader.name}
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                aria-label="إغلاق"
                disabled={
                  saving
                }
                onClick={() =>
                  setOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={save}
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    النتيجة
                  </span>

                  <select
                    value={
                      result
                    }
                    onChange={(
                      event
                    ) =>
                      setResult(
                        event
                          .target
                          .value
                      )
                    }
                  >
                    <option>
                      زيارة
                    </option>
                    <option>
                      اتصال
                    </option>
                    <option>
                      طلب أسعار
                    </option>
                    <option>
                      مهتم
                    </option>
                    <option>
                      غير مهتم
                    </option>
                    <option>
                      طلبية
                    </option>
                  </select>
                </label>

                <label className="field">
                  <span>
                    موعد المتابعة
                  </span>

                  <input
                    type="datetime-local"
                    value={
                      follow
                    }
                    onChange={(
                      event
                    ) =>
                      setFollow(
                        event
                          .target
                          .value
                      )
                    }
                  />

                  <small className="helpText">
                    التوقيت المعتمد: دمشق
                  </small>
                </label>

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={5}
                    value={
                      notes
                    }
                    onChange={(
                      event
                    ) =>
                      setNotes(
                        event
                          .target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              {message ? (
                <div
                  className="toastError"
                  role="alert"
                  aria-live="polite"
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
                  disabled={
                    saving
                  }
                  onClick={() =>
                    setOpen(
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
                  {saving
                    ? "جارٍ الحفظ..."
                    : "حفظ"}
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
  t,
  v,
}: {
  t: string;
  v: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">
        {t}
      </div>

      <div className="statValue">
        {v}
      </div>
    </div>
  );
}

function Info({
  t,
  v,
}: {
  t: string;
  v: string;
}) {
  return (
    <div className="quickItem">
      <div>
        <strong>
          {t}
        </strong>

        <span>
          {v}
        </span>
      </div>
    </div>
  );
}