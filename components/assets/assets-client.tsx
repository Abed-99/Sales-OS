"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { RateField, applyTransactionRate } from "@/components/rate-field";
import { createClient } from "@/lib/supabase/client";

function num(value: unknown) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n : 0;
}

function today() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Damascus",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());

  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";

  return `${get("year")}-${get("month")}-${get("day")}`;
}

function currentMonth() {
  return today().slice(0, 7);
}

function assetError(error: { message?: string } | null) {
  const message = (error?.message ?? "").toLowerCase();
  const map: [string, string][] = [
    ["not allowed", "ما عندك صلاحية لهالعملية."],
    ["financial period is closed", "هالشهر مقفل بالمالية."],
    [
      "cashbox must be active and in the asset currency",
      "الصندوق لازم يكون شغّال وبنفس عملة الأصل.",
    ],
    [
      "in-service date cannot be before purchase date",
      "تاريخ بدء الاستخدام ما بيكون قبل تاريخ الشراء.",
    ],
    ["salvage value cannot exceed cost", "قيمة الخردة ما بتكون أكبر من الكلفة."],
    ["invalid salvage", "قيمة الخردة غلط."],
    ["invalid useful life", "العمر الإنتاجي لازم يكون أكبر من صفر."],
    ["invalid purchase cost", "الكلفة لازم تكون أكبر من صفر."],
    ["asset already disposed", "الأصل مبيوع أو مشطوب من قبل."],
    ["disposal date cannot be before purchase date", "تاريخ البيع ما بيكون قبل تاريخ الشراء."],
    ["missing exchange rate", "ما في سعر صرف مسجّل لعملة الأصل بهاليوم."],
  ];
  return map.find(([key]) => message.includes(key))?.[1] ?? "تعذر تنفيذ العملية. حاول مرة تانية.";
}

export type FixedAsset = {
  id: string;
  asset_number: string;
  name: string;
  category: string | null;
  description: string | null;
  purchase_date: string;
  in_service_date: string;
  currency: string;
  purchase_cost: number;
  salvage_value: number;
  useful_life_months: number;
  depreciation_method: string;
  accumulated_depreciation: number;
  status: "active" | "fully_depreciated" | "disposed";
  disposal_date: string | null;
  disposal_amount: number | null;
  notes: string | null;
  created_at: string;
  book_value: number;
  monthly_depreciation: number;
};

export type AssetDepreciation = {
  id: string;
  asset_id: string;
  period_start: string;
  period_end: string;
  amount: number;
  posted_at: string;
};

export function AssetsClient({
  companyId,
  baseCurrency,
  assets,
  depreciation,
  cashboxes,
  canManage,
  canDepreciate,
}: {
  companyId: string;
  baseCurrency: string;
  assets: FixedAsset[];
  depreciation: AssetDepreciation[];
  cashboxes: { id: string; name: string; currency: string }[];
  canManage: boolean;
  canDepreciate: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();

  const [search, setSearch] = useState("");
  const [open, setOpen] = useState(false);
  const [depreciationOpen, setDepreciationOpen] = useState(false);

  const [name, setName] = useState("");
  const [category, setCategory] = useState("");
  const [description, setDescription] = useState("");
  const [purchaseDate, setPurchaseDate] = useState(today());
  const [serviceDate, setServiceDate] = useState(today());
  const [currency, setCurrency] = useState(baseCurrency);
  const [cost, setCost] = useState("");
  const [salvage, setSalvage] = useState("0");
  const [lifeMonths, setLifeMonths] = useState("60");
  const [notes, setNotes] = useState("");
  // "" = أصل كان عنا قبل النظام، وإلا رقم الصندوق اللي دفعنا منه.
  const [paidFrom, setPaidFrom] = useState("");

  const [depreciationMonth, setDepreciationMonth] = useState(currentMonth());

  const [saving, setSaving] = useState(false);
  const [txRate, setTxRate] = useState("");
  const [message, setMessage] = useState("");

  // بيع أو شطب أصل
  const [disposeAsset, setDisposeAsset] = useState<FixedAsset | null>(null);
  const [disposeMode, setDisposeMode] = useState<"sell" | "scrap">("sell");
  const [disposeAmount, setDisposeAmount] = useState("");
  const [disposeCashbox, setDisposeCashbox] = useState("");
  const [disposeDate, setDisposeDate] = useState(today());
  const [disposeNotes, setDisposeNotes] = useState("");

  function openDispose(asset: FixedAsset) {
    setMessage("");
    setDisposeAsset(asset);
    setDisposeMode("sell");
    setDisposeAmount("");
    setDisposeDate(today());
    setDisposeNotes("");
    setDisposeCashbox(
      cashboxes.find((box) => box.currency.toUpperCase() === asset.currency.toUpperCase())?.id ??
        "",
    );
  }

  async function saveDispose(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!disposeAsset) return;
    const amount = disposeMode === "sell" ? num(disposeAmount) : 0;
    if (disposeMode === "sell" && (amount <= 0 || !disposeCashbox)) {
      setMessage("اكتب سعر البيع واختار الصندوق اللي فات عليه المبلغ.");
      return;
    }
    setSaving(true);
    setMessage("");
    const rateError = await applyTransactionRate(
      supabase,
      companyId,
      disposeAsset.currency,
      baseCurrency,
      disposeDate,
      txRate,
    );

    if (rateError) {
      setSaving(false);
      setMessage(rateError);
      return;
    }

    const { error } = await supabase.rpc("dispose_fixed_asset", {
      target_company: companyId,
      target_asset: disposeAsset.id,
      target_date: disposeDate,
      target_amount: amount,
      target_cashbox: disposeMode === "sell" ? disposeCashbox : null,
      target_notes: disposeNotes.trim() || null,
    });
    setSaving(false);
    if (error) {
      setMessage(assetError(error));
      return;
    }
    setDisposeAsset(null);
    router.refresh();
  }

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();

    if (!q) {
      return assets;
    }

    return assets.filter((asset) =>
      [asset.asset_number, asset.name, asset.category].some((value) =>
        value?.toLowerCase().includes(q),
      ),
    );
  }, [assets, search]);

  const assetCurrencies = [...new Set(assets.map((asset) => asset.currency.trim().toUpperCase()))];

  const mixedAssetCurrencies = assetCurrencies.length > 1;

  const assetDisplayCurrency = assetCurrencies[0] ?? baseCurrency;

  const ownedAssets = assets.filter((asset) => asset.status !== "disposed");

  const totalCost = ownedAssets.reduce((sum, asset) => sum + num(asset.purchase_cost), 0);

  const totalDepreciation = ownedAssets.reduce(
    (sum, asset) => sum + num(asset.accumulated_depreciation),
    0,
  );

  const totalBookValue = ownedAssets.reduce((sum, asset) => sum + num(asset.book_value), 0);

  const activeCount = assets.filter((asset) => asset.status === "active").length;

  async function saveAsset(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!name.trim() || num(cost) <= 0 || num(lifeMonths) <= 0) {
      setMessage("اسم الأصل والتكلفة والعمر الإنتاجي مطلوبين.");
      return;
    }

    setSaving(true);
    setMessage("");

    const rateError = await applyTransactionRate(
      supabase,
      companyId,
      currency,
      baseCurrency,
      purchaseDate,
      txRate,
    );

    if (rateError) {
      setSaving(false);
      setMessage(rateError);
      return;
    }

    const { error } = await supabase.rpc("create_fixed_asset", {
      target_company: companyId,
      target_name: name.trim(),
      target_category: category.trim() || null,
      target_description: description.trim() || null,
      target_purchase_date: purchaseDate,
      target_in_service_date: serviceDate,
      target_currency: currency,
      target_purchase_cost: num(cost),
      target_salvage_value: num(salvage),
      target_useful_life_months: Math.round(num(lifeMonths)),
      target_notes: notes.trim() || null,
      target_cashbox: paidFrom || null,
    });

    setSaving(false);

    if (error) {
      setMessage(assetError(error));
      return;
    }

    setOpen(false);
    setName("");
    setCategory("");
    setDescription("");
    setCost("");
    setSalvage("0");
    setLifeMonths("60");
    setNotes("");
    setPaidFrom("");

    router.refresh();
  }

  async function postDepreciation(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const [year, month] = depreciationMonth.split("-").map(Number);

    if (!year || !month) {
      setMessage("اختار شهر صحيح.");
      return;
    }

    setSaving(true);
    setMessage("");

    const { data, error } = await supabase.rpc("post_asset_depreciation_month", {
      target_company: companyId,
      target_year: year,
      target_month: month,
    });

    setSaving(false);

    if (error) {
      setMessage(assetError(error));
      return;
    }

    setDepreciationOpen(false);

    setMessage(`تم ترحيل الإهلاك لـ ${Number(data || 0)} أصل.`);

    router.refresh();
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">الأصول</span>

          <h2>سجل الأصول الثابتة</h2>

          <p className="muted">سيارات، معدات، أجهزة، أثاث وأي أصل طويل الأجل.</p>
        </div>

        <div className="rowActions">
          {canDepreciate && (
            <button
              type="button"
              className="softButton"
              onClick={() => {
                setMessage("");
                setDepreciationOpen(true);
              }}
            >
              <Icons.chart size={14} />
              ترحيل الإهلاك
            </button>
          )}

          {canManage && (
            <button
              type="button"
              className="primaryButton"
              onClick={() => {
                setMessage("");
                setOpen(true);
              }}
            >
              <Icons.plus size={14} />
              أصل جديد
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini title="الأصول النشطة" value={String(activeCount)} />

        <Mini
          title="تكلفة الأصول"
          value={
            mixedAssetCurrencies ? "حسب العملة" : `${totalCost.toFixed(2)} ${assetDisplayCurrency}`
          }
        />

        <Mini
          title="الإهلاك المتراكم"
          value={
            mixedAssetCurrencies
              ? "حسب العملة"
              : `${totalDepreciation.toFixed(2)} ${assetDisplayCurrency}`
          }
        />

        <Mini
          title="القيمة الدفترية"
          value={
            mixedAssetCurrencies
              ? "حسب العملة"
              : `${totalBookValue.toFixed(2)} ${assetDisplayCurrency}`
          }
        />
      </section>

      <section className="panel" style={{ marginTop: 14 }}>
        <div className="filters">
          <div className="searchBox">
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="بحث برقم الأصل أو الاسم أو التصنيف..."
            />
          </div>

          <div />
          <div />

          <div className="resultCount">{filtered.length} أصل</div>
        </div>

        {!filtered.length ? (
          <div className="empty">
            <Icons.box size={30} />
            <h3>ما في أصول مسجلة</h3>
            <p>أضف السيارات والمعدات والأجهزة المستخدمة بالشركة.</p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الأصل</th>
                  <th>التصنيف</th>
                  <th>التكلفة</th>
                  <th>العمر</th>
                  <th>إهلاك شهري</th>
                  <th>إهلاك متراكم</th>
                  <th>القيمة الدفترية</th>
                  <th>الحالة</th>
                  {canManage ? <th /> : null}
                </tr>
              </thead>

              <tbody>
                {filtered.map((asset) => (
                  <tr key={asset.id}>
                    <td>
                      <strong>{asset.name}</strong>
                      <div className="muted">{asset.asset_number}</div>
                    </td>

                    <td>{asset.category || "—"}</td>

                    <td>
                      {num(asset.purchase_cost).toFixed(2)} {asset.currency}
                    </td>

                    <td>{asset.useful_life_months} شهر</td>

                    <td>{num(asset.monthly_depreciation).toFixed(2)}</td>

                    <td>{num(asset.accumulated_depreciation).toFixed(2)}</td>

                    <td>
                      <strong>{num(asset.book_value).toFixed(2)}</strong>
                    </td>

                    <td>
                      <span
                        className={`chip ${
                          asset.status === "active"
                            ? "green"
                            : asset.status === "fully_depreciated"
                              ? "orange"
                              : "gray"
                        }`}
                      >
                        {asset.status === "active"
                          ? "نشط"
                          : asset.status === "fully_depreciated"
                            ? "مستهلك بالكامل"
                            : num(asset.disposal_amount) > 0
                              ? "مبيوع"
                              : "مشطوب"}
                      </span>
                      {asset.status === "disposed" ? (
                        <div className="muted">
                          {asset.disposal_date}
                          {num(asset.disposal_amount) > 0
                            ? ` • ${num(asset.disposal_amount).toFixed(2)} ${asset.currency}`
                            : ""}
                        </div>
                      ) : null}
                    </td>

                    {canManage ? (
                      <td>
                        {asset.status !== "disposed" ? (
                          <button
                            type="button"
                            className="softButton"
                            onClick={() => openDispose(asset)}
                          >
                            بيع / شطب
                          </button>
                        ) : null}
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="panel panelPad" style={{ marginTop: 14 }}>
        <div className="panelHeader">
          <div>
            <h2>آخر قيود الإهلاك</h2>
            <p>سجل الإهلاك المرحّل</p>
          </div>
        </div>

        {!depreciation.length ? (
          <p className="muted">ما تم ترحيل أي إهلاك لسا.</p>
        ) : (
          <div className="quickList">
            {depreciation.slice(0, 10).map((row) => {
              const asset = assets.find((item) => item.id === row.asset_id);

              return (
                <div className="quickItem" key={row.id}>
                  <div>
                    <strong>{asset?.name || "أصل"}</strong>

                    <span>
                      {row.period_start} → {row.period_end}
                    </span>
                  </div>

                  <div className="count">{num(row.amount).toFixed(2)}</div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      {open && (
        <div className="modalOverlay">
          <section className="modal" style={{ maxWidth: 850 }}>
            <div className="modalHeader">
              <div>
                <span className="eyebrow">أصل ثابت</span>
                <h2>إضافة أصل ثابت</h2>
              </div>

              <button type="button" className="closeButton" onClick={() => setOpen(false)}>
                ×
              </button>
            </div>

            <form onSubmit={saveAsset}>
              <div className="formGrid">
                <Field label="اسم الأصل *" value={name} setValue={setName} />

                <Field label="التصنيف" value={category} setValue={setCategory} />

                <label className="field">
                  <span>تاريخ الشراء</span>
                  <input
                    type="date"
                    value={purchaseDate}
                    onChange={(event) => setPurchaseDate(event.target.value)}
                  />
                </label>

                <label className="field">
                  <span>بداية الاستخدام</span>
                  <input
                    type="date"
                    value={serviceDate}
                    onChange={(event) => setServiceDate(event.target.value)}
                  />
                </label>

                <Field
                  label="العملة"
                  value={currency}
                  setValue={(value) => setCurrency(value.toUpperCase())}
                />

                <label className="field">
                  <span>طريقة الدفع</span>
                  <select value={paidFrom} onChange={(event) => setPaidFrom(event.target.value)}>
                    <option value="">أصل موجود عنا قبل النظام</option>
                    {cashboxes
                      .filter((box) => box.currency.toUpperCase() === currency.toUpperCase())
                      .map((box) => (
                        <option key={box.id} value={box.id}>
                          دفعنا من {box.name}
                        </option>
                      ))}
                  </select>
                </label>

                <NumberField label="تكلفة الشراء *" value={cost} setValue={setCost} />

                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={currency}
                  baseCurrency={baseCurrency}
                  date={purchaseDate}
                  value={txRate}
                  onChange={setTxRate}
                />

                <NumberField label="قيمة الخردة" value={salvage} setValue={setSalvage} />

                <NumberField
                  label="العمر الإنتاجي بالشهور *"
                  value={lifeMonths}
                  setValue={setLifeMonths}
                  step="1"
                />

                <label className="field full">
                  <span>الوصف</span>
                  <textarea
                    rows={3}
                    value={description}
                    onChange={(event) => setDescription(event.target.value)}
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={3}
                    value={notes}
                    onChange={(event) => setNotes(event.target.value)}
                  />
                </label>
              </div>

              {message && <div className="toastError">{message}</div>}

              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setOpen(false)}>
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  حفظ الأصل
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {depreciationOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">الإهلاك</span>
                <h2>ترحيل الإهلاك الشهري</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() => setDepreciationOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={postDepreciation}>
              <div className="formGrid">
                <label className="field full">
                  <span>الشهر</span>

                  <input
                    type="month"
                    value={depreciationMonth}
                    onChange={(event) => setDepreciationMonth(event.target.value)}
                  />
                </label>
              </div>

              <p className="muted">
                النظام يحسب إهلاك القسط الثابت تلقائيًا لكل أصل نشط لم يتم ترحيله بهذا الشهر.
              </p>

              {message && <div className="toastError">{message}</div>}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() => setDepreciationOpen(false)}
                >
                  إلغاء
                </button>

                <button className="primaryButton" disabled={saving}>
                  ترحيل الإهلاك
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {disposeAsset ? (
        <div className="modalOverlay">
          <section className="modal" role="dialog" aria-modal="true">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">بيع أو شطب أصل</span>
                <h2>{disposeAsset.name}</h2>
                <p className="muted">
                  القيمة الدفترية اليوم: {num(disposeAsset.book_value).toFixed(2)}{" "}
                  {disposeAsset.currency}
                </p>
              </div>
              <button type="button" className="closeButton" onClick={() => setDisposeAsset(null)}>
                ×
              </button>
            </div>
            <form onSubmit={saveDispose}>
              <div className="rowActions" style={{ marginBottom: 12 }}>
                <button
                  type="button"
                  className={disposeMode === "sell" ? "primaryButton" : "softButton"}
                  onClick={() => setDisposeMode("sell")}
                >
                  بعناه
                </button>
                <button
                  type="button"
                  className={disposeMode === "scrap" ? "primaryButton" : "softButton"}
                  onClick={() => setDisposeMode("scrap")}
                >
                  شطب (خرب، انسرق، انرمى)
                </button>
              </div>
              <div className="formGrid">
                {disposeMode === "sell" ? (
                  <>
                    <label className="field">
                      <span>سعر البيع ({disposeAsset.currency})</span>
                      <input
                        type="number"
                        min="0"
                        step="0.01"
                        value={disposeAmount}
                        onChange={(event) => setDisposeAmount(event.target.value)}
                      />
                    </label>
                    <label className="field">
                      <span>المبلغ فات على صندوق</span>
                      <select
                        value={disposeCashbox}
                        onChange={(event) => setDisposeCashbox(event.target.value)}
                      >
                        <option value="">اختار</option>
                        {cashboxes
                          .filter(
                            (box) =>
                              box.currency.toUpperCase() === disposeAsset.currency.toUpperCase(),
                          )
                          .map((box) => (
                            <option key={box.id} value={box.id}>
                              {box.name} ({box.currency})
                            </option>
                          ))}
                      </select>
                    </label>
                  </>
                ) : null}
                <label className="field">
                  <span>التاريخ</span>
                  <input
                    type="date"
                    value={disposeDate}
                    onChange={(event) => setDisposeDate(event.target.value)}
                  />
                </label>

                <RateField
                  supabase={supabase}
                  companyId={companyId}
                  currency={disposeAsset.currency}
                  baseCurrency={baseCurrency}
                  date={disposeDate}
                  value={txRate}
                  onChange={setTxRate}
                />
                <label className="field">
                  <span>ملاحظة</span>
                  <input
                    value={disposeNotes}
                    placeholder={disposeMode === "sell" ? "لمين بعناه..." : "شو صار فيه..."}
                    onChange={(event) => setDisposeNotes(event.target.value)}
                  />
                </label>
              </div>
              {(() => {
                const diff =
                  (disposeMode === "sell" ? num(disposeAmount) : 0) - num(disposeAsset.book_value);
                if (disposeMode === "sell" && !num(disposeAmount)) return null;
                return (
                  <p
                    className={diff >= 0 ? "kpiPositive" : "kpiNegative"}
                    style={{ marginTop: 12 }}
                  >
                    {diff >= 0 ? "ربح" : "خسارة"}: {Math.abs(diff).toFixed(2)}{" "}
                    {disposeAsset.currency}
                  </p>
                );
              })()}
              {message ? <div className="toastError">{message}</div> : null}
              <div className="modalActions">
                <button type="button" className="softButton" onClick={() => setDisposeAsset(null)}>
                  إلغاء
                </button>
                <button className="primaryButton" disabled={saving}>
                  {saving ? "عم نحفظ..." : disposeMode === "sell" ? "تسجيل البيع" : "تسجيل الشطب"}
                </button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function Field({
  label,
  value,
  setValue,
}: {
  label: string;
  value: string;
  setValue: (value: string) => void;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <input value={value} onChange={(event) => setValue(event.target.value)} />
    </label>
  );
}

function NumberField({
  label,
  value,
  setValue,
  step = "0.01",
}: {
  label: string;
  value: string;
  setValue: (value: string) => void;
  step?: string;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <input
        type="number"
        min="0"
        step={step}
        value={value}
        onChange={(event) => setValue(event.target.value)}
      />
    </label>
  );
}

function Mini({ title, value }: { title: string; value: string }) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>
      <div className="statValue">{value}</div>
    </div>
  );
}
