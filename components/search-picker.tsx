"use client";

import { useEffect, useMemo, useRef, useState } from "react";

export type PickerOption<T = unknown> = {
  id: string;
  label: string;
  hint?: string | null;
  /** Exact code (SKU / barcode). Typing or scanning it then Enter picks the option at once. */
  code?: string | null;
  data?: T;
};

/**
 * خانة اختيار بالبحث: بتفلتر القائمة المحمّلة، وإذا في `onSearch` بتجيب من القاعدة
 * كمان — فما في حد لعدد الزبائن أو الأصناف.
 */
export function SearchPicker<T>({
  value,
  options,
  onChange,
  onSearch,
  placeholder = "اكتب للبحث...",
  disabled,
  emptyText = "ما في نتائج",
  autoFocus,
}: {
  value: string;
  options: PickerOption<T>[];
  onChange: (id: string, option: PickerOption<T> | null) => void;
  onSearch?: (term: string) => Promise<PickerOption<T>[]>;
  placeholder?: string;
  disabled?: boolean;
  emptyText?: string;
  autoFocus?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [term, setTerm] = useState("");
  const [remote, setRemote] = useState<PickerOption<T>[]>([]);
  const [loading, setLoading] = useState(false);
  const [active, setActive] = useState(0);
  // الخيار المختار ممكن يكون جاي من البحث ومش من القائمة المحمّلة.
  const [picked, setPicked] = useState<PickerOption<T> | null>(null);
  const boxRef = useRef<HTMLDivElement>(null);

  const selected = useMemo(
    () => options.find((option) => option.id === value) ?? (picked?.id === value ? picked : null),
    [options, value, picked],
  );

  const results = useMemo(() => {
    const q = term.trim().toLowerCase();
    const local = q
      ? options.filter((option) =>
          [option.label, option.hint, option.code].some((text) =>
            text?.toLowerCase().includes(q),
          ),
        )
      : options;
    const seen = new Set(local.map((option) => option.id));
    return [...local, ...remote.filter((option) => !seen.has(option.id))].slice(0, 50);
  }, [options, remote, term]);

  useEffect(() => {
    const q = term.trim();
    if (!onSearch || q.length < 2) {
      setRemote([]);
      return;
    }
    let cancelled = false;
    setLoading(true);
    const timer = window.setTimeout(async () => {
      try {
        const rows = await onSearch(q);
        if (!cancelled) setRemote(rows);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 250);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [term, onSearch]);

  useEffect(() => {
    function close(event: MouseEvent) {
      if (!boxRef.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, []);

  function choose(option: PickerOption<T> | null) {
    setPicked(option);
    onChange(option?.id ?? "", option);
    setTerm("");
    setOpen(false);
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setOpen(true);
      setActive((index) => Math.min(index + 1, results.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActive((index) => Math.max(index - 1, 0));
    } else if (event.key === "Enter") {
      if (!open && !term) return;
      event.preventDefault();
      const exact = results.find(
        (option) => option.code && option.code.toLowerCase() === term.trim().toLowerCase(),
      );
      const option = exact ?? results[active];
      if (option) choose(option);
      else setOpen(false);
    } else if (event.key === "Escape") {
      setOpen(false);
    }
  }

  return (
    <div className="picker" ref={boxRef}>
      <input
        value={open ? term : (selected?.label ?? "")}
        placeholder={selected ? selected.label : placeholder}
        disabled={disabled}
        autoFocus={autoFocus}
        onFocus={() => {
          setOpen(true);
          setActive(0);
        }}
        onChange={(event) => {
          setTerm(event.target.value);
          setOpen(true);
          setActive(0);
        }}
        onKeyDown={onKeyDown}
        // لما تطلع من الخانة (Tab أو كبسة برا) القائمة بتتسكّر لحتى ما تغطّي الخانات التانية.
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
        role="combobox"
        aria-expanded={open}
        autoComplete="off"
      />
      {open ? (
        <div className="pickerMenu" role="listbox">
          {results.map((option, index) => (
            <button
              type="button"
              key={option.id}
              role="option"
              aria-selected={option.id === value}
              className={`pickerOption${index === active ? " active" : ""}`}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => choose(option)}
            >
              <strong>{option.label}</strong>
              {option.hint ? <span>{option.hint}</span> : null}
            </button>
          ))}
          {!results.length ? (
            <div className="pickerEmpty">{loading ? "عم نبحث..." : emptyText}</div>
          ) : null}
          {loading && results.length ? <div className="pickerEmpty">عم نبحث...</div> : null}
        </div>
      ) : null}
    </div>
  );
}
