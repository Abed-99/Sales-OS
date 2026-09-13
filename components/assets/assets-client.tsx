"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

function num(value: unknown) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? n : 0;
}

function today() {
  const parts =
    new Intl.DateTimeFormat(
      "en-US",
      {
        timeZone: "Asia/Damascus",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }
    ).formatToParts(
      new Date()
    );

  const get = (type: string) =>
    parts.find(
      (part) =>
        part.type === type
    )?.value ?? "";

  return `${get("year")}-${get("month")}-${get("day")}`;
}

function currentMonth() {
  return today().slice(0, 7);
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
  status:
    | "active"
    | "fully_depreciated"
    | "disposed";
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
  canManage,
  canDepreciate,
}: {
  companyId: string;
  baseCurrency: string;
  assets: FixedAsset[];
  depreciation: AssetDepreciation[];
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

  const [depreciationMonth, setDepreciationMonth] =
    useState(currentMonth());

  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();

    if (!q) {
      return assets;
    }

    return assets.filter((asset) =>
      [
        asset.asset_number,
        asset.name,
        asset.category,
      ].some((value) =>
        value?.toLowerCase().includes(q)
      )
    );
  }, [assets, search]);

  const assetCurrencies =
    [
      ...new Set(
        assets.map(
          (asset) =>
            asset.currency
              .trim()
              .toUpperCase()
        )
      ),
    ];

  const mixedAssetCurrencies =
    assetCurrencies.length > 1;

  const assetDisplayCurrency =
    assetCurrencies[0] ??
    baseCurrency;

  const totalCost = assets.reduce(
    (sum, asset) => sum + num(asset.purchase_cost),
    0
  );

  const totalDepreciation = assets.reduce(
    (sum, asset) =>
      sum + num(asset.accumulated_depreciation),
    0
  );

  const totalBookValue = assets.reduce(
    (sum, asset) => sum + num(asset.book_value),
    0
  );

  const activeCount = assets.filter(
    (asset) => asset.status === "active"
  ).length;

  async function saveAsset(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!name.trim() || num(cost) <= 0 || num(lifeMonths) <= 0) {
      setMessage(
        "اسم الأصل والتكلفة والعمر الإنتاجي مطلوبين."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } = await supabase.rpc(
      "create_fixed_asset",
      {
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
      }
    );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ العملية على الأصل. تحقق من البيانات والصلاحيات والفترة المالية.");
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

    router.refresh();
  }

  async function postDepreciation(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    const [year, month] = depreciationMonth
      .split("-")
      .map(Number);

    if (!year || !month) {
      setMessage("اختار شهر صحيح.");
      return;
    }

    setSaving(true);
    setMessage("");

    const { data, error } = await supabase.rpc(
      "post_asset_depreciation_month",
      {
        target_company: companyId,
        target_year: year,
        target_month: month,
      }
    );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ العملية على الأصل. تحقق من البيانات والصلاحيات والفترة المالية.");
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
          <span className="eyebrow">
            Fixed Assets
          </span>

          <h2>
            سجل الأصول الثابتة
          </h2>

          <p className="muted">
            سيارات، معدات، أجهزة، أثاث وأي أصل طويل الأجل.
          </p>
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
        <Mini
          title="الأصول النشطة"
          value={String(activeCount)}
        />

        <Mini
          title="تكلفة الأصول"
          value={mixedAssetCurrencies ? "حسب العملة" : `${totalCost.toFixed(2)} ${assetDisplayCurrency}`}
        />

        <Mini
          title="الإهلاك المتراكم"
          value={mixedAssetCurrencies ? "حسب العملة" : `${totalDepreciation.toFixed(2)} ${assetDisplayCurrency}`}
        />

        <Mini
          title="القيمة الدفترية"
          value={mixedAssetCurrencies ? "حسب العملة" : `${totalBookValue.toFixed(2)} ${assetDisplayCurrency}`}
        />
      </section>

      <section
        className="panel"
        style={{ marginTop: 14 }}
      >
        <div className="filters">
          <div className="searchBox">
            <Icons.search size={16} />

            <input
              value={search}
              onChange={(event) =>
                setSearch(event.target.value)
              }
              placeholder="بحث برقم الأصل أو الاسم..."
            />
          </div>

          <div />
          <div />

          <div className="resultCount">
            {filtered.length} أصل
          </div>
        </div>

        {!filtered.length ? (
          <div className="empty">
            <Icons.box size={30} />
            <h3>ما في أصول مسجلة</h3>
            <p>
              أضف السيارات والمعدات والأجهزة المستخدمة بالشركة.
            </p>
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
                </tr>
              </thead>

              <tbody>
                {filtered.map((asset) => (
                  <tr key={asset.id}>
                    <td>
                      <strong>{asset.name}</strong>
                      <div className="muted">
                        {asset.asset_number}
                      </div>
                    </td>

                    <td>
                      {asset.category || "—"}
                    </td>

                    <td>
                      {num(asset.purchase_cost).toFixed(2)}{" "}
                      {asset.currency}
                    </td>

                    <td>
                      {asset.useful_life_months} شهر
                    </td>

                    <td>
                      {num(asset.monthly_depreciation).toFixed(2)}
                    </td>

                    <td>
                      {num(asset.accumulated_depreciation).toFixed(2)}
                    </td>

                    <td>
                      <strong>
                        {num(asset.book_value).toFixed(2)}
                      </strong>
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
                          : "مستبعد"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section
        className="panel panelPad"
        style={{ marginTop: 14 }}
      >
        <div className="panelHeader">
          <div>
            <h2>آخر قيود الإهلاك</h2>
            <p>سجل الإهلاك المرحّل</p>
          </div>
        </div>

        {!depreciation.length ? (
          <p className="muted">
            ما تم ترحيل أي إهلاك لسا.
          </p>
        ) : (
          <div className="quickList">
            {depreciation.slice(0, 10).map((row) => {
              const asset = assets.find(
                (item) => item.id === row.asset_id
              );

              return (
                <div
                  className="quickItem"
                  key={row.id}
                >
                  <div>
                    <strong>
                      {asset?.name || "أصل"}
                    </strong>

                    <span>
                      {row.period_start} → {row.period_end}
                    </span>
                  </div>

                  <div className="count">
                    {num(row.amount).toFixed(2)}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>

      {open && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{ maxWidth: 850 }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Fixed Asset
                </span>
                <h2>إضافة أصل ثابت</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() => setOpen(false)}
              >
                ×
              </button>
            </div>

            <form onSubmit={saveAsset}>
              <div className="formGrid">
                <Field
                  label="اسم الأصل *"
                  value={name}
                  setValue={setName}
                />

                <Field
                  label="التصنيف"
                  value={category}
                  setValue={setCategory}
                />

                <label className="field">
                  <span>تاريخ الشراء</span>
                  <input
                    type="date"
                    value={purchaseDate}
                    onChange={(event) =>
                      setPurchaseDate(event.target.value)
                    }
                  />
                </label>

                <label className="field">
                  <span>بداية الاستخدام</span>
                  <input
                    type="date"
                    value={serviceDate}
                    onChange={(event) =>
                      setServiceDate(event.target.value)
                    }
                  />
                </label>

                <Field
                  label="العملة"
                  value={currency}
                  setValue={(value) =>
                    setCurrency(value.toUpperCase())
                  }
                />

                <NumberField
                  label="تكلفة الشراء *"
                  value={cost}
                  setValue={setCost}
                />

                <NumberField
                  label="قيمة الخردة"
                  value={salvage}
                  setValue={setSalvage}
                />

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
                    onChange={(event) =>
                      setDescription(event.target.value)
                    }
                  />
                </label>

                <label className="field full">
                  <span>ملاحظات</span>
                  <textarea
                    rows={3}
                    value={notes}
                    onChange={(event) =>
                      setNotes(event.target.value)
                    }
                  />
                </label>
              </div>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() => setOpen(false)}
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
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
                <span className="eyebrow">
                  Depreciation
                </span>
                <h2>ترحيل الإهلاك الشهري</h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setDepreciationOpen(false)
                }
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
                    onChange={(event) =>
                      setDepreciationMonth(
                        event.target.value
                      )
                    }
                  />
                </label>
              </div>

              <p className="muted">
                النظام يحسب إهلاك القسط الثابت تلقائيًا
                لكل أصل نشط لم يتم ترحيله بهذا الشهر.
              </p>

              {message && (
                <div className="toastError">
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setDepreciationOpen(false)
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  ترحيل الإهلاك
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
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
      <input
        value={value}
        onChange={(event) =>
          setValue(event.target.value)
        }
      />
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
        onChange={(event) =>
          setValue(event.target.value)
        }
      />
    </label>
  );
}

function Mini({
  title,
  value,
}: {
  title: string;
  value: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">{title}</div>
      <div className="statValue">{value}</div>
    </div>
  );
}