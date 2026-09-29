"use client";

import Link from "next/link";
import { useRef, useState } from "react";

export type Letterhead = {
  name: string;
  phone: string | null;
  whatsapp: string | null;
  address: string | null;
  logo_url: string | null;
  tax_number?: string | null;
  tax_label?: string | null;
};

/** رقم واتساب بصيغة wa.me (أرقام بس، بدون +). */
function waNumber(phone: string | null | undefined) {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) return digits.slice(2);
  if (digits.startsWith("09")) return `963${digits.slice(1)}`;
  return digits;
}

/**
 * إطار صفحة الطباعة: أزرار (طباعة، PDF، واتساب، مع/بدون ترويسة) وورقة A4.
 * الـ PDF بينعمل من الورقة نفسها (صورة عالية الدقة) فالعربي بيطلع متل ما هو.
 */
export function PrintShell({
  company,
  fileName,
  shareText,
  phone,
  backHref,
  tools,
  children,
}: {
  company: Letterhead;
  fileName: string;
  shareText: string;
  phone?: string | null;
  backHref: string;
  /** أدوات إضافية بشريط الأزرار (ما بتطلع بالطباعة ولا بالـ PDF). */
  tools?: React.ReactNode;
  children: React.ReactNode;
}) {
  const paperRef = useRef<HTMLDivElement>(null);
  const [withHeader, setWithHeader] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function makePdf() {
    const [{ default: html2canvas }, { jsPDF }] = await Promise.all([
      import("html2canvas"),
      import("jspdf"),
    ]);
    const node = paperRef.current!;
    const canvas = await html2canvas(node, { scale: 2, backgroundColor: "#ffffff" });
    const pdf = new jsPDF({ unit: "mm", format: "a4" });
    const pageWidth = 210;
    const pageHeight = 297;
    const imgHeight = (canvas.height * pageWidth) / canvas.width;
    const image = canvas.toDataURL("image/jpeg", 0.92);
    let offset = 0;
    pdf.addImage(image, "JPEG", 0, 0, pageWidth, imgHeight);
    while (imgHeight - offset > pageHeight + 1) {
      offset += pageHeight;
      pdf.addPage();
      pdf.addImage(image, "JPEG", 0, -offset, pageWidth, imgHeight);
    }
    return pdf.output("blob");
  }

  async function download() {
    setBusy(true);
    setMessage("");
    try {
      const blob = await makePdf();
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${fileName}.pdf`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 5000);
    } catch {
      setMessage("ما قدرنا نعمل الـ PDF.");
    } finally {
      setBusy(false);
    }
  }

  async function sendWhatsApp() {
    setBusy(true);
    setMessage("");
    try {
      const blob = await makePdf();
      const file = new File([blob], `${fileName}.pdf`, { type: "application/pdf" });
      // الموبايل: بتنفتح المشاركة، بتختار واتساب والزبون، والملف بيروح متل ما هو.
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], text: shareText, title: fileName });
        return;
      }
      // الكمبيوتر: بينزل الملف وبتنفتح محادثة الزبون، بتسحب الملف عالمحادثة.
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${fileName}.pdf`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 5000);
      const number = waNumber(phone);
      window.open(
        `https://wa.me/${number}?text=${encodeURIComponent(shareText)}`,
        "_blank",
        "noopener",
      );
      setMessage("نزل الملف. اسحبو لمحادثة واتساب اللي انفتحت.");
    } catch (error) {
      if ((error as Error)?.name !== "AbortError") setMessage("ما قدرنا نجهّز الإرسال.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="printPage">
      <div className="printToolbar">
        <Link className="softButton" href={backHref}>
          رجوع
        </Link>
        <label className="printToggle">
          <input
            type="checkbox"
            checked={withHeader}
            onChange={(event) => setWithHeader(event.target.checked)}
          />
          ترويسة الشركة (رسمي)
        </label>
        <button type="button" className="softButton" onClick={() => window.print()}>
          طباعة
        </button>
        <button
          type="button"
          className="softButton"
          disabled={busy}
          onClick={() => void download()}
        >
          PDF
        </button>
        <button
          type="button"
          className="primaryButton"
          disabled={busy}
          onClick={() => void sendWhatsApp()}
        >
          {busy ? "عم نجهّز..." : "إرسال عالواتساب"}
        </button>
        {message ? <span className="muted">{message}</span> : null}
        {tools}
      </div>

      <div className="printPaper" ref={paperRef}>
        {withHeader ? (
          <header className="printHeader">
            {company.logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={company.logo_url} alt="" className="printLogo" crossOrigin="anonymous" />
            ) : null}
            <div>
              <h1>{company.name}</h1>
              <p>
                {company.address ? <span>{company.address}</span> : null}
                {company.phone ? (
                  <span>
                    {company.address ? " • " : ""}
                    <bdi dir="ltr">{company.phone}</bdi>
                  </span>
                ) : null}
                {company.tax_number ? (
                  <span>
                    {company.address || company.phone || company.whatsapp ? " • " : ""}
                    {"الرقم الضريبي "}

                    <bdi dir="ltr">{company.tax_number}</bdi>
                  </span>
                ) : null}
                {company.whatsapp ? (
                  <span>
                    {company.address || company.phone ? " • " : ""}
                    {"واتساب "}
                    <bdi dir="ltr">{company.whatsapp}</bdi>
                  </span>
                ) : null}
              </p>
            </div>
          </header>
        ) : null}
        {children}
      </div>
    </div>
  );
}
