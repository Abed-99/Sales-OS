"use client";
import { safeFileName } from "@/lib/format";

/** رقم واتساب بصيغة دولية بدون + (963...). */
export function waNumber(phone: string | null | undefined) {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) return digits.slice(2);
  if (digits.startsWith("09")) return `963${digits.slice(1)}`;
  return digits;
}

export function isPhoneDevice() {
  return typeof navigator !== "undefined" && /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

export type DesktopMode = "app" | "web";

export function getDesktopMode(): DesktopMode {
  try {
    return (localStorage.getItem("wa-desktop-mode") as DesktopMode) || "app";
  } catch {
    return "app";
  }
}

export function setDesktopMode(mode: DesktopMode) {
  try {
    localStorage.setItem("wa-desktop-mode", mode);
  } catch {
    // التخزين مسكّر بالمتصفح: منضل على الافتراضي
  }
}

/** بيفتح صفحة الطباعة بإطار مخفي وبيصوّر الورقة (نفس اللي بينطبع). */
async function captureDocument(url: string): Promise<HTMLCanvasElement> {
  const iframe = document.createElement("iframe");
  iframe.style.cssText = "position:fixed;left:-10000px;top:0;width:900px;height:1300px;border:0;";
  iframe.src = url;
  document.body.appendChild(iframe);
  try {
    await new Promise<void>((resolve, reject) => {
      iframe.onload = () => resolve();
      setTimeout(() => reject(new Error("timeout")), 20000);
    });
    let paper: HTMLElement | null = null;
    for (let i = 0; i < 60 && !paper; i++) {
      paper = iframe.contentDocument?.querySelector(".printPaper") ?? null;
      if (!paper) await new Promise((r) => setTimeout(r, 150));
    }
    if (!paper) throw new Error("document not found");
    await iframe.contentDocument?.fonts?.ready;
    const { default: html2canvas } = await import("html2canvas");
    return await html2canvas(paper, { scale: 2, backgroundColor: "#ffffff" });
  } finally {
    iframe.remove();
  }
}

async function canvasToPdf(canvas: HTMLCanvasElement) {
  const { jsPDF } = await import("jspdf");
  const pdf = new jsPDF({ unit: "mm", format: "a4" });
  const width = 210;
  const height = (canvas.height * width) / canvas.width;
  const image = canvas.toDataURL("image/jpeg", 0.92);
  let offset = 0;
  pdf.addImage(image, "JPEG", 0, 0, width, height);
  while (height - offset > 298) {
    offset += 297;
    pdf.addPage();
    pdf.addImage(image, "JPEG", 0, -offset, width, height);
  }
  return pdf.output("blob");
}

function canvasToPng(canvas: HTMLCanvasElement) {
  return new Promise<Blob>((resolve, reject) =>
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("png"))), "image/png"),
  );
}

export type SendResult = "shared" | "opened" | "opened-with-image" | "cancelled";

/**
 * الإرسال "نص آلي": البرنامج بيجهّز، والمستخدم بيكبس إرسال بواتساب.
 * - الموبايل: قائمة المشاركة مع الـ PDF والنص ← بيختار واتساب والتاجر.
 * - الكمبيوتر: بيفتح محادثة التاجر والنص مكتوب، والورقة (إذا في) بالحافظة كصورة ← Ctrl+V.
 */
export async function sendViaWhatsApp({
  phone,
  text,
  documentUrl,
  fileName,
}: {
  phone: string | null;
  text: string;
  documentUrl?: string | null;
  fileName?: string;
}): Promise<SendResult> {
  const number = waNumber(phone);

  if (isPhoneDevice()) {
    if (documentUrl) {
      const canvas = await captureDocument(documentUrl);
      const pdf = await canvasToPdf(canvas);
      const file = new File([pdf], `${safeFileName(fileName ?? "")}.pdf`, { type: "application/pdf" });
      if (navigator.canShare?.({ files: [file] })) {
        try {
          await navigator.share({ files: [file], text });
          return "shared";
        } catch (error) {
          if ((error as Error)?.name === "AbortError") return "cancelled";
          throw error;
        }
      }
    }
    window.location.href = `https://wa.me/${number}?text=${encodeURIComponent(text)}`;
    return "opened";
  }

  let withImage = false;
  if (documentUrl && typeof ClipboardItem !== "undefined" && navigator.clipboard?.write) {
    // الصورة بتنحط بالحافظة (الوعد بيحافظ على إذن الكبسة لحد ما تجهز).
    const png = captureDocument(documentUrl).then(canvasToPng);
    await navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
    withImage = true;
  }

  const link =
    getDesktopMode() === "app"
      ? `whatsapp://send?phone=${number}&text=${encodeURIComponent(text)}`
      : `https://web.whatsapp.com/send?phone=${number}&text=${encodeURIComponent(text)}`;
  if (link.startsWith("whatsapp://")) window.location.href = link;
  else window.open(link, "whatsapp-web");

  return withImage ? "opened-with-image" : "opened";
}
