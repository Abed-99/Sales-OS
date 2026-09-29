"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

/** اختيار فترة الكشف (بيختفي بالطباعة). */
export function StatementRange({ from, to }: { from: string; to: string }) {
  const router = useRouter();
  const params = useSearchParams();
  const [start, setStart] = useState(from);
  const [end, setEnd] = useState(to);

  return (
    <form
      className="printRange"
      onSubmit={(event) => {
        event.preventDefault();
        const next = new URLSearchParams(params.toString());
        if (start) next.set("from", start);
        else next.delete("from");
        if (end) next.set("to", end);
        router.push(`?${next.toString()}`);
      }}
    >
      <label>
        من <input type="date" value={start} onChange={(event) => setStart(event.target.value)} />
      </label>
      <label>
        لـ <input type="date" value={end} onChange={(event) => setEnd(event.target.value)} />
      </label>
      <button className="softButton">عرض</button>
    </form>
  );
}
