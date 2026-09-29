"use client";

import { useEffect, useRef, useState } from "react";

type Detector = { detect: (source: HTMLVideoElement) => Promise<{ rawValue: string }[]> };

declare global {
  interface Window {
    BarcodeDetector?: new (options?: { formats?: string[] }) => Detector;
  }
}

/**
 * زر 📷: بيفتح كاميرا الموبايل الخلفية وبيقرأ الباركود (بالمتصفحات اللي بتدعم BarcodeDetector،
 * متل كروم أندرويد). إذا ما في دعم، الزر ما بيطلع وبيضل المسح بجهاز الباركود أو الكتابة.
 */
export function BarcodeScanButton({ onDetect }: { onDetect: (code: string) => void }) {
  const [supported, setSupported] = useState(false);
  const [open, setOpen] = useState(false);
  const [error, setError] = useState("");
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    setSupported(typeof window !== "undefined" && "BarcodeDetector" in window);
  }, []);

  useEffect(() => {
    if (!open) return;
    let stream: MediaStream | null = null;
    let stopped = false;
    let timer = 0;

    async function start() {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
        });
        const video = videoRef.current!;
        video.srcObject = stream;
        await video.play();
        const detector = new window.BarcodeDetector!({
          formats: ["ean_13", "ean_8", "code_128", "code_39", "upc_a", "upc_e", "qr_code"],
        });
        const tick = async () => {
          if (stopped) return;
          try {
            const codes = await detector.detect(video);
            if (codes[0]?.rawValue) {
              onDetect(codes[0].rawValue);
              setOpen(false);
              return;
            }
          } catch {
            // الإطار ما كان جاهز، منجرّب اللي بعدو
          }
          timer = window.setTimeout(tick, 250);
        };
        void tick();
      } catch {
        setError("ما قدرنا نفتح الكاميرا. اسمح للمتصفح يستعملها.");
      }
    }

    void start();
    return () => {
      stopped = true;
      window.clearTimeout(timer);
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, [open, onDetect]);

  if (!supported) return null;

  return (
    <>
      <button
        type="button"
        className="softButton"
        aria-label="مسح باركود بالكاميرا"
        onClick={() => {
          setError("");
          setOpen(true);
        }}
      >
        📷
      </button>
      {open ? (
        <div className="modalOverlay" style={{ zIndex: 1400 }}>
          <section className="modal" style={{ maxWidth: 420 }}>
            <div className="modalHeader">
              <h2>وجّه الكاميرا عالباركود</h2>
              <button type="button" className="closeButton" onClick={() => setOpen(false)}>
                ×
              </button>
            </div>
            <video ref={videoRef} playsInline muted style={{ width: "100%", borderRadius: 12 }} />
            {error ? <div className="toastError">{error}</div> : null}
          </section>
        </div>
      ) : null}
    </>
  );
}
