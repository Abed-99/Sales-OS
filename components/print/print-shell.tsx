"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { safeFileName } from "@/lib/format";

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
    // الـ PDF دايمًا بعرض ورقة A4 حتى لو الشاشة موبايل، بعدين منرجّع الورقة متل ما كانت.
    const previousStyle = node.style.cssText;
    node.style.width = "794px";
    node.style.maxWidth = "794px";
    node.style.minHeight = "1123px";
    try {
      return await paginate(node, html2canvas, jsPDF);
    } finally {
      node.style.cssText = previousStyle;
    }
  }

  async function paginate(
    node: HTMLDivElement,
    html2canvas: typeof import("html2canvas").default,
    jsPDF: typeof import("jspdf").jsPDF,
  ) {
    const scale = 2;
    const canvas = await html2canvas(node, {
      scale,
      backgroundColor: "#ffffff",
      windowWidth: Math.max(window.innerWidth, 900),
    });
    const pdf = new jsPDF({ unit: "mm", format: "a4" });

    // الورقة بتنقسم على صفحات A4، والقص بيصير بين السطور (مش بنص سطر).
    const top = node.getBoundingClientRect().top;
    const pagePx = (node.offsetWidth * 297) / 210;
    const margin = 36; // فراغ فوق وتحت بالصفحات اللي بعد الأولى
    const total = node.offsetHeight;
    const cuts = Array.from(
      node.querySelectorAll(
        "tr, .printTotals, .printNote, .printSigns, .printFooter",
      ),
    )
      .map((el) => el.getBoundingClientRect().bottom - top)
      .sort((a, b) => a - b);
    // عناوين الجدول بتنعاد فوق كل صفحة بتكمّل نفس الجدول.
    const tables = Array.from(node.querySelectorAll("table")).map((table) => {
      const box = table.getBoundingClientRect();
      const head = table.tHead?.getBoundingClientRect();
      return {
        top: box.top - top,
        bottom: box.bottom - top,
        headTop: head ? head.top - top : 0,
        headHeight: head ? head.height : 0,
      };
    });
    const headerAt = (y: number) =>
      tables.find(
        (t) => t.headHeight && y > t.headTop + t.headHeight && y < t.bottom - 1,
      );

    const slices: [number, number][] = [];
    let start = 0;
    while (start < total - 1) {
      const repeat = slices.length ? headerAt(start) : undefined;
      const room =
        pagePx -
        (slices.length ? margin : 0) -
        margin -
        (repeat ? repeat.headHeight : 0);
      let end = start + room;
      if (!slices.length && total <= pagePx + 1) end = total;
      else if (end >= total) end = total;
      else {
        const fit = cuts.filter((c) => c > start + 40 && c <= end).pop();
        if (fit) end = fit;
      }
      slices.push([start, end]);
      start = end;
    }
    slices.forEach(([from, to], index) => {
      const page = document.createElement("canvas");
      page.width = canvas.width;
      page.height = Math.round(pagePx * scale);
      const ctx = page.getContext("2d")!;
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, page.width, page.height);
      let offsetY = index ? margin * scale : 0;
      const repeat = index ? headerAt(from) : undefined;
      if (repeat) {
        const h = Math.round(repeat.headHeight * scale);
        ctx.drawImage(
          canvas,
          0,
          Math.round(repeat.headTop * scale),
          canvas.width,
          h,
          0,
          offsetY,
          canvas.width,
          h,
        );
        offsetY += h;
      }
      ctx.drawImage(
        canvas,
        0,
        Math.round(from * scale),
        canvas.width,
        Math.round((to - from) * scale),
        0,
        offsetY,
        canvas.width,
        Math.round((to - from) * scale),
      );
      if (slices.length > 1) {
        ctx.fillStyle = "#7a8884";
        ctx.font = `${11 * scale}px Tahoma, Arial, sans-serif`;
        ctx.textAlign = "center";
        ctx.direction = "rtl";
        ctx.fillText(
          `صفحة ${index + 1} من ${slices.length}`,
          page.width / 2,
          page.height - 14 * scale,
        );
      }
      if (index) pdf.addPage();
      pdf.addImage(page.toDataURL("image/jpeg", 0.92), "JPEG", 0, 0, 210, 297);
    });
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
      link.download = `${safeFileName(fileName)}.pdf`;
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
      const file = new File([blob], `${safeFileName(fileName)}.pdf`, {
        type: "application/pdf",
      });
      // الموبايل: بتنفتح المشاركة، بتختار واتساب والزبون، والملف بيروح متل ما هو.
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({
          files: [file],
          text: shareText,
          title: fileName,
        });
        return;
      }
      // الكمبيوتر: بينزل الملف وبتنفتح محادثة الزبون، بتسحب الملف عالمحادثة.
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${safeFileName(fileName)}.pdf`;
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
      if ((error as Error)?.name !== "AbortError")
        setMessage("ما قدرنا نجهّز الإرسال.");
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
        <button
          type="button"
          className="softButton"
          onClick={() => window.print()}
        >
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
            <div className="printBrand">
              {company.logo_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={company.logo_url}
                  alt=""
                  className="printLogo"
                  crossOrigin="anonymous"
                />
              ) : (
                <span className="printMonogram">
                  {company.name.trim().charAt(0)}
                </span>
              )}
              <div>
                <h1>{company.name}</h1>
                <p>
                  {company.address ? <span>{company.address}</span> : null}
                  {company.tax_number ? (
                    <>
                      {company.address ? <br /> : null}
                      {"الرقم الضريبي "}
                      <bdi dir="ltr">{company.tax_number}</bdi>
                    </>
                  ) : null}
                </p>
              </div>
            </div>
            {company.phone || company.whatsapp ? (
              <div className="printContacts">
                {company.phone ? (
                  <div>
                    {"هاتف "}
                    <bdi dir="ltr">{company.phone}</bdi>
                  </div>
                ) : null}
                {company.whatsapp ? (
                  <div>
                    {"واتساب "}
                    <bdi dir="ltr">{company.whatsapp}</bdi>
                  </div>
                ) : null}
              </div>
            ) : null}
          </header>
        ) : null}
        {children}
        {withHeader ? (
          <footer className="printFooter">
            <div>
              <span>{company.name}</span>
              <span>
                {company.phone || company.whatsapp ? (
                  <bdi dir="ltr">{company.whatsapp || company.phone}</bdi>
                ) : null}
              </span>
            </div>
          </footer>
        ) : null}
      </div>
    </div>
  );
}
