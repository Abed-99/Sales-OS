"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
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
  latitude: number | string | null;
  longitude: number | string | null;
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
  next_follow_up_at: string | null;
};

export type TraderOrderRow = {
  id: string;
  status: string;
  total: number;
  created_at: string;
};

export function TraderDetailClient({
  companyId,
  trader,
  initialVisits,
  orders,
}: {
  companyId: string;
  trader: TraderDetailRow;
  initialVisits: TraderVisitRow[];
  orders: TraderOrderRow[];
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();

  const [visits, setVisits] =
    useState<TraderVisitRow[]>(initialVisits);
  const [open, setOpen] = useState(false);
  const [result, setResult] = useState("زيارة");
  const [notes, setNotes] = useState("");
  const [follow, setFollow] = useState("");
  const [saving, setSaving] = useState(false);

  const total = orders.reduce(
    (sum, order) => sum + Number(order.total || 0),
    0
  );

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setSaving(true);

    const { data, error } = await supabase
      .from("trader_visits")
      .insert({
        company_id: companyId,
        trader_id: trader.id,
        result,
        notes: notes.trim() || null,
        contacted_at: new Date().toISOString(),
        next_follow_up_at: follow
          ? new Date(follow).toISOString()
          : null,
      })
      .select(
        "id,result,notes,contacted_at,next_follow_up_at"
      )
      .single();

    setSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    setVisits((current) => [
      data as TraderVisitRow,
      ...current,
    ]);
    setOpen(false);
    setNotes("");
    setFollow("");
    router.refresh();
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">ملف التاجر</span>
          <h2>{trader.name}</h2>
          <p className="muted">
            {trader.area || "بدون منطقة"}
            {trader.contact_name
              ? ` • ${trader.contact_name}`
              : ""}
          </p>
        </div>

        <div className="rowActions">
          {trader.phone && (
            <a
              className="softButton"
              href={`tel:${trader.phone}`}
            >
              <Icons.phone size={14} /> اتصال
            </a>
          )}

          {trader.whatsapp && (
            <a
              className="primaryButton"
              target="_blank"
              rel="noreferrer"
              href={`https://wa.me/${trader.whatsapp.replace(/\D/g, "")}`}
            >
              <Icons.whatsapp size={14} /> واتساب
            </a>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini t="عدد الزيارات" v={String(visits.length)} />
        <Mini t="الطلبات" v={String(orders.length)} />
        <Mini t="إجمالي المبيعات" v={total.toFixed(2)} />
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
              <h2>سجل الزيارات والمتابعات</h2>
              <p>كل تواصل مع التاجر بمكان واحد</p>
            </div>

            <button
              className="primaryButton"
              onClick={() => setOpen(true)}
            >
              <Icons.plus size={14} /> سجل تواصل
            </button>
          </div>

          {!visits.length ? (
            <div className="empty">
              <Icons.calendar size={28} />
              <h3>ما في زيارات مسجلة</h3>
              <p>سجل أول زيارة أو اتصال.</p>
            </div>
          ) : (
            <div className="quickList">
              {visits.map((visit) => (
                <div
                  className="quickItem"
                  key={visit.id}
                >
                  <div className="quickIcon">
                    <Icons.calendar size={16} />
                  </div>

                  <div>
                    <strong>{visit.result}</strong>
                    <span>
                      {visit.notes || "بدون ملاحظات"} •{" "}
                      {new Date(
                        visit.contacted_at
                      ).toLocaleString("ar")}
                    </span>
                  </div>

                  <div className="count">
                    {visit.next_follow_up_at
                      ? `متابعة ${new Date(
                          visit.next_follow_up_at
                        ).toLocaleDateString("ar")}`
                      : "تم"}
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>

        <aside className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>معلومات التاجر</h2>
              <p>بيانات سريعة</p>
            </div>
          </div>

          <div className="quickList">
            <Info t="الهاتف" v={trader.phone || "—"} />
            <Info
              t="واتساب"
              v={trader.whatsapp || "—"}
            />
            <Info
              t="العنوان"
              v={trader.address || "—"}
            />
            <Info t="الحالة" v={trader.status} />

            {trader.latitude != null &&
              trader.longitude != null && (
                <Link
                  className="softButton"
                  href={`/map?trader=${trader.id}`}
                >
                  <Icons.map size={14} /> فتح على الخريطة
                </Link>
              )}
          </div>

          <div
            className="panelHeader"
            style={{ marginTop: 20 }}
          >
            <div>
              <h2>آخر الطلبات</h2>
            </div>
          </div>

          {!orders.length ? (
            <p className="muted">ما عنده طلبات لسا.</p>
          ) : (
            <div className="quickList">
              {orders.slice(0, 5).map((order) => (
                <Link
                  key={order.id}
                  href={`/orders?order=${order.id}`}
                  className="quickItem"
                  style={{ textDecoration: "none" }}
                >
                  <div className="quickIcon">
                    <Icons.cart size={15} />
                  </div>

                  <div>
                    <strong>
                      طلب {order.id.slice(0, 8)}
                    </strong>
                    <span>
                      {order.status} •{" "}
                      {new Date(
                        order.created_at
                      ).toLocaleDateString("ar")}
                    </span>
                  </div>

                  <div className="count">
                    {Number(order.total).toFixed(2)}
                  </div>
                </Link>
              ))}
            </div>
          )}
        </aside>
      </div>

      {open && (
        <div
          className="modalOverlay"
          onMouseDown={(event) => {
            if (
              event.target === event.currentTarget &&
              !saving
            ) {
              setOpen(false);
            }
          }}
        >
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  متابعة جديدة
                </span>
                <h2>سجل تواصل مع {trader.name}</h2>
              </div>

              <button
                className="closeButton"
                onClick={() => setOpen(false)}
                disabled={saving}
              >
                ×
              </button>
            </div>

            <form onSubmit={save}>
              <div className="formGrid">
                <label className="field">
                  <span>النتيجة</span>
                  <select
                    value={result}
                    onChange={(event) =>
                      setResult(event.target.value)
                    }
                  >
                    <option>زيارة</option>
                    <option>اتصال</option>
                    <option>طلب أسعار</option>
                    <option>مهتم</option>
                    <option>غير مهتم</option>
                    <option>طلبية</option>
                  </select>
                </label>

                <label className="field">
                  <span>موعد المتابعة</span>
                  <input
                    type="datetime-local"
                    value={follow}
                    onChange={(event) =>
                      setFollow(event.target.value)
                    }
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={5}
                    value={notes}
                    onChange={(event) =>
                      setNotes(event.target.value)
                    }
                  />
                </label>
              </div>

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() => setOpen(false)}
                  disabled={saving}
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving
                    ? "عم نحفظ..."
                    : "حفظ"}
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
  t,
  v,
}: {
  t: string;
  v: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">{t}</div>
      <div className="statValue">{v}</div>
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
        <strong>{t}</strong>
        <span>{v}</span>
      </div>
    </div>
  );
}
