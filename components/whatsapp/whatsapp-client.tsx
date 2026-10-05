"use client";

import Link from "next/link";
import { useMemo, useState } from "react";

import { Icons } from "@/components/icons";
import {
  OutboxPanel,
  WhatsAppSettingsPanel,
  type OutboxMessage,
} from "@/components/whatsapp/outbox-panel";
import { formatMoney as money, phoneText } from "@/lib/format";

export type DebtorRow = {
  id: string;
  name: string;
  phone: string | null;
  balance: number;
  overdue: number;
  currency: string;
};

export type OptInRow = {
  id: string;
  name: string;
  phone: string | null;
  whatsapp: string | null;
  area: string | null;
};

/** رقم واتساب بصيغة wa.me (أرقام بس). */
function waNumber(phone: string | null | undefined) {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) return digits.slice(2);
  if (digits.startsWith("09")) return `963${digits.slice(1)}`;
  return digits;
}

function openChat(phone: string | null, text: string) {
  window.open(
    `https://wa.me/${waNumber(phone)}?text=${encodeURIComponent(text)}`,
    "_blank",
    "noopener",
  );
}

export function WhatsAppClient({
  companyId,
  companyName,
  debtors,
  optIns,
  pending,
  recent,
  settings,
  templates,
  defaults,
  canManageSettings,
}: {
  companyId: string;
  companyName: string;
  debtors: DebtorRow[];
  optIns: OptInRow[];
  pending: OutboxMessage[];
  recent: OutboxMessage[];
  settings: Parameters<typeof WhatsAppSettingsPanel>[0]["settings"];
  templates: Record<string, string>;
  defaults: Record<string, string>;
  canManageSettings: boolean;
}) {
  const [tab, setTab] = useState<"outbox" | "debts" | "campaign" | "settings">("outbox");
  const [template, setTemplate] = useState(
    `مرحبا {الاسم}، عنا عروض جديدة على البضاعة الكهربائية هالأسبوع. تواصل معنا للتفاصيل.\n${companyName}`,
  );
  const [sent, setSent] = useState<Set<string>>(new Set());
  const [area, setArea] = useState("");

  const areas = useMemo(
    () => [
      ...new Set(optIns.map((row) => row.area).filter((value): value is string => Boolean(value))),
    ],
    [optIns],
  );
  const audience = optIns.filter(
    (row) => (!area || row.area === area) && (row.whatsapp || row.phone),
  );
  const next = audience.find((row) => !sent.has(row.id));

  function sendTo(row: OptInRow) {
    openChat(row.whatsapp || row.phone, template.replaceAll("{الاسم}", row.name));
    setSent((current) => new Set(current).add(row.id));
  }

  return (
    <div className="page">
      <div className="rowActions" style={{ marginBottom: 14 }}>
        <button
          type="button"
          className={tab === "outbox" ? "primaryButton" : "softButton"}
          onClick={() => setTab("outbox")}
        >
          📬 رسائل جاهزة ({pending.length})
        </button>
        <button
          type="button"
          className={tab === "debts" ? "primaryButton" : "softButton"}
          onClick={() => setTab("debts")}
        >
          تذكير بالديون ({debtors.length})
        </button>
        <button
          type="button"
          className={tab === "campaign" ? "primaryButton" : "softButton"}
          onClick={() => setTab("campaign")}
        >
          حملة ({optIns.length} موافق)
        </button>
        {canManageSettings ? (
          <button
            type="button"
            className={tab === "settings" ? "primaryButton" : "softButton"}
            onClick={() => setTab("settings")}
          >
            ⚙️ إعدادات الرسائل
          </button>
        ) : null}
      </div>

      {tab === "outbox" ? (
        <OutboxPanel companyId={companyId} pending={pending} recent={recent} />
      ) : tab === "settings" ? (
        <WhatsAppSettingsPanel
          companyId={companyId}
          settings={settings}
          templates={templates}
          defaults={defaults}
        />
      ) : tab === "debts" ? (
        <section className="panel">
          <div className="panelHeader panelPad">
            <div>
              <h2>زبائن عليهن ديون</h2>
              <p>المتأخر أول. «كشف حساب» بيعمل PDF بتبعتو عالواتساب.</p>
            </div>
          </div>
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الزبون</th>
                  <th>الدين</th>
                  <th>متأخر</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {debtors.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.name}</strong>
                      <div className="muted" dir="ltr" style={{ textAlign: "right" }}>
                        {phoneText(row.phone) || "بدون رقم"}
                      </div>
                    </td>
                    <td>{money(row.balance, row.currency)}</td>
                    <td className={row.overdue > 0 ? "kpiNegative" : ""}>
                      {row.overdue > 0 ? money(row.overdue, row.currency) : "—"}
                    </td>
                    <td>
                      <div className="rowActions">
                        <button
                          type="button"
                          className="softButton"
                          disabled={!row.phone}
                          onClick={() =>
                            openChat(
                              row.phone,
                              `مرحبا ${row.name}، نذكّرك بلطف إنو عليك رصيد ${money(row.balance, row.currency)}${
                                row.overdue > 0
                                  ? ` (منو ${money(row.overdue, row.currency)} متأخر)`
                                  : ""
                              }. شكرًا إلك. ${companyName}`,
                            )
                          }
                        >
                          <Icons.whatsapp size={14} /> رسالة تذكير
                        </button>
                        <Link className="softButton" href={`/print/customer/${row.id}`}>
                          كشف حساب PDF
                        </Link>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!debtors.length ? <p className="muted panelPad">ما في زبائن عليهن ديون.</p> : null}
          </div>
        </section>
      ) : (
        <section className="panel panelPad">
          <div className="panelHeader">
            <div>
              <h2>حملة واتساب</h2>
              <p>
                بتروح بس للزبائن اللي وافقوا يستلموا رسائل (من ملف الزبون). اكتب {"{الاسم}"} وبينحط
                اسم كل زبون.
              </p>
            </div>
          </div>

          <label className="field">
            <span>الرسالة</span>
            <textarea
              rows={4}
              value={template}
              onChange={(event) => setTemplate(event.target.value)}
            />
          </label>

          {areas.length ? (
            <label className="field" style={{ marginTop: 10, maxWidth: 280 }}>
              <span>المنطقة</span>
              <select value={area} onChange={(event) => setArea(event.target.value)}>
                <option value="">كل المناطق</option>
                {areas.map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
              </select>
            </label>
          ) : null}

          <div className="rowActions" style={{ marginTop: 12, alignItems: "center" }}>
            <button
              type="button"
              className="primaryButton"
              disabled={!next || !template.trim()}
              onClick={() => next && sendTo(next)}
            >
              {next ? `إرسال للتالي: ${next.name}` : "خلصت القائمة ✓"}
            </button>
            <span className="muted">
              انبعت {audience.filter((row) => sent.has(row.id)).length} من {audience.length}
            </span>
            {sent.size ? (
              <button type="button" className="softButton" onClick={() => setSent(new Set())}>
                من الأول
              </button>
            ) : null}
          </div>
          <p className="muted" style={{ marginTop: 6 }}>
            واتساب العادي ما بيسمح بالإرسال الجماعي التلقائي، فكل كبسة بتفتح محادثة الزبون والرسالة
            جاهزة، بتكبس إرسال وبترجع. (مع واتساب Business API بيصير تلقائي.)
          </p>

          <div className="quickList" style={{ marginTop: 12 }}>
            {audience.map((row) => (
              <div className="quickItem" key={row.id}>
                <div className="quickIcon">
                  {sent.has(row.id) ? "✓" : <Icons.whatsapp size={14} />}
                </div>
                <div>
                  <strong>{row.name}</strong>
                  <span>{[row.area, row.whatsapp || row.phone].filter(Boolean).join(" • ")}</span>
                </div>
                <button type="button" className="softButton" onClick={() => sendTo(row)}>
                  إرسال
                </button>
              </div>
            ))}
            {!audience.length ? (
              <p className="muted">
                ما في زبائن موافقين. من ملف الزبون فعّل «يوافق على رسائل واتساب».
              </p>
            ) : null}
          </div>
        </section>
      )}
    </div>
  );
}
