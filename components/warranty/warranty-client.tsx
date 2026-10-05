"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";
import { phoneText } from "@/lib/format";

type Relation<T> = T | T[] | null;
const one = <T,>(value: Relation<T>) => (Array.isArray(value) ? (value[0] ?? null) : value);

type Claim = {
  id: string;
  claim_date: string;
  issue: string;
  status: "open" | "repaired" | "replaced" | "rejected";
  resolution: string | null;
};

type SerialResult = {
  id: string;
  serial: string;
  status: string;
  product: string;
  trader: string | null;
  trader_phone: string | null;
  invoice_number: string | null;
  sold_on: string | null;
  warranty_until: string | null;
  in_warranty: boolean;
  claims: Claim[];
};

export type OpenClaim = {
  id: string;
  claim_date: string;
  issue: string;
  status: string;
  in_warranty: boolean;
  product_serials: Relation<{
    serial: string;
    warranty_until: string | null;
    products: Relation<{ name: string }>;
    traders: Relation<{ name: string }>;
  }>;
};

const claimLabels: Record<Claim["status"], string> = {
  open: "مفتوحة",
  repaired: "تصلّحت",
  replaced: "تبدّلت",
  rejected: "انرفضت",
};

export function WarrantyClient({
  companyId,
  openClaims,
  canEdit,
}: {
  companyId: string;
  openClaims: OpenClaim[];
  canEdit: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();
  const [serial, setSerial] = useState("");
  const [results, setResults] = useState<SerialResult[] | null>(null);
  const [issue, setIssue] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function search(event?: React.FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    if (!serial.trim()) return;
    setBusy(true);
    setMessage("");
    const { data, error } = await supabase.rpc("lookup_serial", {
      target_company: companyId,
      target_serial: serial.trim(),
    });
    setBusy(false);
    if (error) return setMessage("ما قدرنا نبحث.");
    setResults((data ?? []) as SerialResult[]);
  }

  async function addClaim(serialId: string) {
    if (!issue.trim()) return setMessage("اكتب شو المشكلة.");
    setBusy(true);
    const { error } = await supabase.rpc("save_warranty_claim", {
      target_company: companyId,
      target_serial_id: serialId,
      target_claim: null,
      target_issue: issue.trim(),
      target_status: null,
      target_resolution: null,
    });
    setBusy(false);
    if (error) return setMessage("ما قدرنا نسجّل الشكوى.");
    setIssue("");
    await search();
    router.refresh();
  }

  async function closeClaim(serialId: string | null, claimId: string, status: Claim["status"]) {
    const resolution = window.prompt("شو انعمل؟ (اختياري)") ?? "";
    const { error } = await supabase.rpc("save_warranty_claim", {
      target_company: companyId,
      target_serial_id: serialId,
      target_claim: claimId,
      target_issue: null,
      target_status: status,
      target_resolution: resolution,
    });
    if (error) return setMessage("ما قدرنا نحدّث الشكوى.");
    if (results) await search();
    router.refresh();
  }

  return (
    <div className="page">
      <section className="panel panelPad">
        <form className="rowActions" onSubmit={search}>
          <div className="searchBox" style={{ flex: 1, minWidth: 240 }}>
            <Icons.search size={14} />
            <input
              dir="ltr"
              autoFocus
              value={serial}
              onChange={(event) => setSerial(event.target.value)}
              placeholder="الرقم التسلسلي (أو امسحو)"
            />
          </div>
          <button className="primaryButton" disabled={busy}>
            بحث
          </button>
        </form>

        {message ? (
          <div className="toastError" style={{ marginTop: 10 }}>
            {message}
          </div>
        ) : null}

        {results && !results.length ? (
          <p className="muted" style={{ marginTop: 12 }}>
            ما لقينا هالرقم. تأكد منو، أو يمكن ما انسجّل وقت البيع.
          </p>
        ) : null}

        {(results ?? []).map((row) => (
          <div key={row.id} className="panel panelPad" style={{ marginTop: 14 }}>
            <div className="panelHeader">
              <div>
                <h2 dir="ltr" style={{ textAlign: "right" }}>
                  {row.serial}
                </h2>
                <p>{row.product}</p>
              </div>
              <span className={`chip ${row.in_warranty ? "green" : "orange"}`}>
                {row.warranty_until
                  ? row.in_warranty
                    ? `بالضمان لغاية ${row.warranty_until}`
                    : `انتهى الضمان ${row.warranty_until}`
                  : "بدون ضمان"}
              </span>
            </div>
            <p className="muted">
              الزبون: {row.trader ?? "—"} {row.trader_phone ? `• ${phoneText(row.trader_phone)}` : ""} •
              الفاتورة: {row.invoice_number ?? "—"} • تاريخ البيع: {row.sold_on ?? "—"}
            </p>

            {row.claims.length ? (
              <div className="quickList" style={{ marginTop: 10 }}>
                {row.claims.map((claim) => (
                  <div className="quickItem" key={claim.id}>
                    <div>
                      <strong>
                        {claim.claim_date}: {claim.issue}
                      </strong>
                      <span>
                        {claimLabels[claim.status]}
                        {claim.resolution ? ` — ${claim.resolution}` : ""}
                      </span>
                    </div>
                    {canEdit && claim.status === "open" ? (
                      <div className="rowActions">
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => void closeClaim(row.id, claim.id, "repaired")}
                        >
                          تصلّحت
                        </button>
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => void closeClaim(row.id, claim.id, "replaced")}
                        >
                          تبدّلت
                        </button>
                        <button
                          type="button"
                          className="dangerButton"
                          onClick={() => void closeClaim(row.id, claim.id, "rejected")}
                        >
                          رفض
                        </button>
                      </div>
                    ) : null}
                  </div>
                ))}
              </div>
            ) : null}

            {canEdit ? (
              <div className="rowActions" style={{ marginTop: 12 }}>
                <input
                  style={{
                    flex: 1,
                    minWidth: 200,
                    background: "#06110e",
                    color: "white",
                    border: "1px solid var(--line)",
                    borderRadius: 10,
                    padding: 9,
                  }}
                  placeholder="شكوى جديدة: شو المشكلة؟"
                  value={issue}
                  onChange={(event) => setIssue(event.target.value)}
                />
                <button
                  type="button"
                  className="primaryButton"
                  disabled={busy}
                  onClick={() => void addClaim(row.id)}
                >
                  تسجيل شكوى صيانة
                </button>
              </div>
            ) : null}
          </div>
        ))}
      </section>

      <section className="panel" style={{ marginTop: 14 }}>
        <div className="panelHeader panelPad">
          <div>
            <h2>شكاوى مفتوحة</h2>
            <p>قطع بالصيانة لسا ما خلصت</p>
          </div>
        </div>
        <div className="tableWrap">
          <table className="dataTable">
            <thead>
              <tr>
                <th>التاريخ</th>
                <th>القطعة</th>
                <th>الزبون</th>
                <th>المشكلة</th>
                <th>الضمان</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {openClaims.map((claim) => {
                const unit = one(claim.product_serials);
                return (
                  <tr key={claim.id}>
                    <td>{claim.claim_date}</td>
                    <td>
                      <strong>{one(unit?.products ?? null)?.name}</strong>
                      <div className="muted" dir="ltr">
                        {unit?.serial}
                      </div>
                    </td>
                    <td>{one(unit?.traders ?? null)?.name ?? "—"}</td>
                    <td>{claim.issue}</td>
                    <td>
                      <span className={`chip ${claim.in_warranty ? "green" : "orange"}`}>
                        {claim.in_warranty ? "ضمن الضمان" : "خارج الضمان"}
                      </span>
                    </td>
                    <td>
                      {canEdit ? (
                        <button
                          type="button"
                          className="softButton"
                          onClick={() => void closeClaim(null, claim.id, "repaired")}
                        >
                          خلصت
                        </button>
                      ) : null}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {!openClaims.length ? <p className="muted panelPad">ما في شكاوى مفتوحة.</p> : null}
        </div>
      </section>
    </div>
  );
}
