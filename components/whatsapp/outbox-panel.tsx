"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";
import {
  getDesktopMode,
  isPhoneDevice,
  sendViaWhatsApp,
  setDesktopMode,
  type DesktopMode,
} from "@/lib/wa-send";
import { NumberInput } from "@/components/number-input";
import { phoneText } from "@/lib/format";

export type OutboxMessage = {
  id: string;
  kind: "invoice" | "receipt" | "delivery" | "reminder" | "statement" | "custom";
  trader_id: string | null;
  phone: string | null;
  message: string;
  document_type: "invoice" | "statement" | "receipt" | null;
  document_id: string | null;
  status: "pending" | "sent" | "skipped";
  created_at: string;
  sent_at: string | null;
  traders:
    | { name: string; phone?: string | null; whatsapp?: string | null }
    | { name: string; phone?: string | null; whatsapp?: string | null }[]
    | null;
};

const kindLabels: Record<OutboxMessage["kind"], string> = {
  invoice: "🧾 فاتورة",
  receipt: "💵 إيصال قبض",
  delivery: "🚚 توصيل",
  reminder: "⏰ تذكير دين",
  statement: "📄 كشف حساب",
  custom: "✉️ رسالة",
};

const name = (row: OutboxMessage) =>
  (Array.isArray(row.traders) ? row.traders[0]?.name : row.traders?.name) ?? "";

/** رقم الزبون الحالي (إذا انضاف أو تغيّر بعد ما انجهّزت الرسالة). */
const phoneOf = (row: OutboxMessage) => {
  const trader = Array.isArray(row.traders) ? row.traders[0] : row.traders;
  return trader?.whatsapp || trader?.phone || row.phone;
};

function documentUrl(row: OutboxMessage) {
  if (row.document_type === "invoice" && row.document_id)
    return `/print/invoice/${row.document_id}`;
  if (row.document_type === "statement" && row.document_id)
    return `/print/customer/${row.document_id}`;
  if (row.document_type === "receipt" && row.document_id)
    return `/print/receipt/${row.document_id}`;
  return null;
}

export function OutboxPanel({
  companyId,
  pending,
  recent,
}: {
  companyId: string;
  pending: OutboxMessage[];
  recent: OutboxMessage[];
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [texts, setTexts] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState("");
  const [mode, setMode] = useState<DesktopMode>("app");
  const [onPhone, setOnPhone] = useState(false);

  // نوع الجهاز والإعداد المحفوظ بينعرفوا بعد ما تفتح الصفحة (مشان ما يختلف عن السيرفر).
  useEffect(() => {
    setMode(getDesktopMode());
    setOnPhone(isPhoneDevice());
  }, []);

  async function mark(row: OutboxMessage, status: "sent" | "skipped" | "pending") {
    await supabase.rpc("mark_whatsapp_outbox", {
      target_company: companyId,
      target_message: row.id,
      target_status: status,
      target_text: texts[row.id] ?? null,
    });
    router.refresh();
  }

  async function send(row: OutboxMessage) {
    setBusy(row.id);
    setNotice("");
    try {
      const result = await sendViaWhatsApp({
        phone: phoneOf(row),
        text: texts[row.id] ?? row.message,
        documentUrl: documentUrl(row),
        fileName: `${kindLabels[row.kind].slice(2)} ${name(row)}`,
      });
      if (result === "cancelled") return;
      if (result === "opened-with-image") {
        setNotice(
          "انفتحت المحادثة والرسالة مكتوبة. الورقة منسوخة: اكبس Ctrl+V بالمحادثة وبعدين Enter.",
        );
      }
      await mark(row, "sent");
    } catch {
      setNotice("ما قدرنا نجهّز الإرسال. جرّب مرة تانية.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="panel panelPad">
      <div className="panelHeader">
        <div>
          <h2>📬 رسائل جاهزة للإرسال ({pending.length})</h2>
          <p>
            {onPhone
              ? "كبسة «إرسال» بتفتح المشاركة: اختار واتساب والتاجر، والملف والرسالة جاهزين."
              : "كبسة «إرسال» بتفتح محادثة التاجر والرسالة مكتوبة. إذا في فاتورة أو كشف، بيكونوا منسوخين: Ctrl+V وبعدين Enter."}
          </p>
        </div>
        {!onPhone ? (
          <label className="field" style={{ minWidth: 190 }}>
            <span>افتح بـ</span>
            <select
              value={mode}
              onChange={(event) => {
                const next = event.target.value as DesktopMode;
                setMode(next);
                setDesktopMode(next);
              }}
            >
              <option value="app">تطبيق واتساب عالكمبيوتر</option>
              <option value="web">واتساب ويب (المتصفح)</option>
            </select>
          </label>
        ) : null}
      </div>

      {notice ? (
        <div className="toastSuccess" style={{ marginBottom: 10 }}>
          {notice}
        </div>
      ) : null}

      <div className="quickList">
        {pending.map((row) => (
          <div className="outboxCard" key={row.id}>
            <div className="outboxHead">
              <span className="chip blue">{kindLabels[row.kind]}</span>
              <strong>{name(row)}</strong>
              <span className="muted" dir="ltr">
                {phoneText(phoneOf(row)) || "⚠️ ما في رقم"}
              </span>
              {documentUrl(row) ? <span className="chip green">📎 مع الملف</span> : null}
            </div>
            <textarea
              rows={5}
              value={texts[row.id] ?? row.message}
              onChange={(event) =>
                setTexts((current) => ({ ...current, [row.id]: event.target.value }))
              }
            />
            <div className="rowActions">
              <button
                type="button"
                className="primaryButton"
                disabled={busy === row.id}
                onClick={() => void send(row)}
              >
                <Icons.whatsapp size={14} /> {busy === row.id ? "عم نجهّز..." : "إرسال"}
              </button>
              <button type="button" className="softButton" onClick={() => void mark(row, "sent")}>
                انبعتت ✓
              </button>
              <button
                type="button"
                className="softButton"
                onClick={() => void mark(row, "skipped")}
              >
                تجاهل
              </button>
            </div>
          </div>
        ))}
        {!pending.length ? <p className="muted">ما في رسائل ناطرة. كلشي انبعت ✓</p> : null}
      </div>

      {recent.length ? (
        <>
          <h3 style={{ marginTop: 20 }}>آخر المبعوت</h3>
          <div className="quickList">
            {recent.map((row) => (
              <div className="quickItem" key={row.id}>
                <div className="quickIcon">{row.status === "sent" ? "✓" : "—"}</div>
                <div>
                  <strong>
                    {kindLabels[row.kind]} • {name(row)}
                  </strong>
                  <span>
                    {row.status === "sent" ? "انبعتت" : "تجاهلناها"}{" "}
                    {(row.sent_at ?? row.created_at).slice(0, 16).replace("T", " ")}
                  </span>
                </div>
                <button
                  type="button"
                  className="softButton"
                  onClick={() => void mark(row, "pending")}
                >
                  رجّعها
                </button>
              </div>
            ))}
          </div>
        </>
      ) : null}
    </section>
  );
}

type Settings = Record<"invoice" | "receipt" | "delivery" | "reminder" | "statement", boolean> & {
  reminder_days: number;
};

const settingLabels: Record<keyof Omit<Settings, "reminder_days">, string> = {
  invoice: "الفاتورة لما تنعمل",
  receipt: "إيصال لما تقبض من الزبون",
  delivery: "تنبيه لما الطلبية تطلع مع السائق",
  reminder: "تذكير بالديون المتأخرة",
  statement: "كشف حساب أول كل شهر",
};

export function WhatsAppSettingsPanel({
  companyId,
  settings,
  templates,
  defaults,
}: {
  companyId: string;
  settings: Settings;
  templates: Record<string, string>;
  defaults: Record<string, string>;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [value, setValue] = useState<Settings>(settings);
  const [texts, setTexts] = useState<Record<string, string>>(templates);
  const [message, setMessage] = useState("");

  async function save() {
    const { error } = await supabase
      .from("companies")
      .update({ whatsapp_settings: value, whatsapp_templates: texts })
      .eq("id", companyId);
    setMessage(error ? "ما قدرنا نحفظ (بدها صلاحية إعدادات الشركة)." : "انحفظ ✓");
    router.refresh();
  }

  return (
    <section className="panel panelPad">
      <div className="panelHeader">
        <div>
          <h2>شو البرنامج يجهّزلك؟</h2>
          <p>
            المتغيّرات بالقوالب: {"{الاسم} {الرقم} {المبلغ} {الباقي} {الشركة} {السائق} {الشهر}"}.
            فاضي = القالب الافتراضي.
          </p>
        </div>
      </div>
      <div className="quickList">
        {(Object.keys(settingLabels) as (keyof typeof settingLabels)[]).map((kind) => (
          <div className="outboxCard" key={kind}>
            <label className="printToggle" style={{ color: "inherit" }}>
              <input
                type="checkbox"
                checked={value[kind]}
                onChange={(event) => setValue({ ...value, [kind]: event.target.checked })}
              />
              <strong>{settingLabels[kind]}</strong>
            </label>
            {value[kind] ? (
              <textarea
                rows={3}
                placeholder={defaults[kind]}
                value={texts[kind] ?? ""}
                onChange={(event) => setTexts({ ...texts, [kind]: event.target.value })}
              />
            ) : null}
            {kind === "reminder" && value.reminder ? (
              <label className="field" style={{ maxWidth: 240 }}>
                <span>كل كم يوم نذكّر نفس الزبون؟</span>
                <NumberInput
                  min="1"
                  max="60"
                  value={value.reminder_days}
                  onChange={(event) =>
                    setValue({
                      ...value,
                      reminder_days: Math.max(1, Number(event.target.value) || 7),
                    })
                  }
                />
              </label>
            ) : null}
          </div>
        ))}
      </div>
      <div className="rowActions" style={{ marginTop: 12 }}>
        <button type="button" className="primaryButton" onClick={() => void save()}>
          حفظ
        </button>
        {message ? <span className="muted">{message}</span> : null}
      </div>
    </section>
  );
}
