"use client";

import { useState, type RefObject } from "react";

import {
  buildXlsx,
  cellValue,
  downloadBlob,
  tablesToSheets,
  type Cell,
  type Sheet,
} from "@/lib/xlsx";
import { safeFileName } from "@/lib/format";

/**
 * أزرار تصدير التقرير المعروض: Excel (كل جدول بورقة، والأرقام أرقام حقيقية) و PDF (ورقة بيضا).
 * بتاخد اللي ظاهر عالشاشة، فالفلاتر والتواريخ نفسها.
 */
export function ReportExport({
  target,
  fileName,
  title,
  subtitle,
}: {
  target: RefObject<HTMLElement | null>;
  fileName: string;
  title: string;
  subtitle: string;
}) {
  const [busy, setBusy] = useState<"" | "excel" | "pdf">("");
  const [message, setMessage] = useState("");

  function excel() {
    const root = target.current;
    if (!root) return;
    setBusy("excel");
    setMessage("");
    try {
      const sheets: Sheet[] = [];
      // البطاقات والأسطر (مش جداول) بورقة "الملخص".
      const summary: Cell[][] = [[title, subtitle]];
      root.querySelectorAll<HTMLElement>(".statCard").forEach((card) => {
        const label = card.querySelector(".statLabel")?.textContent?.trim() ?? "";
        const value = card.querySelector(".statValue")?.textContent ?? "";
        summary.push([label, cellValue(value)]);
      });
      root.querySelectorAll<HTMLElement>("[data-lines]").forEach((list) => {
        const heading = list.closest("section")?.querySelector("h2")?.textContent?.trim();
        if (heading) summary.push([], [heading]);
        list.querySelectorAll<HTMLElement>(".quickItem").forEach((item) => {
          summary.push([
            item.querySelector("strong")?.textContent?.trim() ?? "",
            cellValue(item.querySelector(".count")?.textContent ?? ""),
          ]);
        });
      });
      if (summary.length > 1) sheets.push({ name: "الملخص", rows: summary });
      sheets.push(...tablesToSheets(root, title));
      if (!sheets.length) {
        setMessage("ما في أرقام بهالتقرير لنصدّرها.");
        return;
      }
      downloadBlob(buildXlsx(sheets), `${safeFileName(fileName, "report")}.xlsx`);
    } finally {
      setBusy("");
    }
  }

  async function pdf() {
    const root = target.current;
    if (!root) return;
    setBusy("pdf");
    setMessage("");
    try {
      const [{ default: html2canvas }, { jsPDF }] = await Promise.all([
        import("html2canvas"),
        import("jspdf"),
      ]);
      const canvas = await html2canvas(root, {
        scale: 2,
        backgroundColor: "#ffffff",
        // نسخة فاتحة للورقة (البرنامج غامق)، مع عنوان التقرير، وبلا أزرار.
        onclone: (doc, clone) => {
          clone.classList.add("exportLight");
          const header = doc.createElement("div");
          header.className = "exportHeader";
          header.innerHTML = `<strong></strong><span></span>`;
          header.querySelector("strong")!.textContent = title;
          header.querySelector("span")!.textContent = subtitle;
          clone.prepend(header);
        },
      });
      const doc = new jsPDF({ unit: "mm", format: "a4" });
      const pageWidth = 210;
      const pageHeight = 297;
      const margin = 8;
      const width = pageWidth - margin * 2;
      // منقطّع الصورة لصفحات (كل صفحة قطعة من الصورة).
      const pagePixels = Math.floor(((pageHeight - margin * 2) * canvas.width) / width);
      for (let y = 0, page = 0; y < canvas.height; y += pagePixels, page++) {
        const slice = document.createElement("canvas");
        slice.width = canvas.width;
        slice.height = Math.min(pagePixels, canvas.height - y);
        slice.getContext("2d")!.drawImage(canvas, 0, -y);
        if (page > 0) doc.addPage();
        doc.addImage(
          slice.toDataURL("image/jpeg", 0.92),
          "JPEG",
          margin,
          margin,
          width,
          (slice.height * width) / canvas.width,
        );
      }
      doc.save(`${safeFileName(fileName, "report")}.pdf`);
    } catch {
      setMessage("ما قدرنا نطلّع الـ PDF. جرّب مرة تانية.");
    } finally {
      setBusy("");
    }
  }

  return (
    <div className="rowActions" data-html2canvas-ignore>
      <button type="button" className="softButton" disabled={!!busy} onClick={excel}>
        {busy === "excel" ? "عم نجهّز..." : "Excel"}
      </button>
      <button type="button" className="softButton" disabled={!!busy} onClick={() => void pdf()}>
        {busy === "pdf" ? "عم نجهّز..." : "PDF"}
      </button>
      {message ? (
        <span className="invalidText" style={{ fontSize: 11 }}>
          {message}
        </span>
      ) : null}
    </div>
  );
}
