"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Icons } from "@/components/icons";

export type Product = {
  id: string;
  category_id: string | null;
  sku: string | null;
  name: string;
  brand: string | null;
  unit: string;
  sale_price: number | null;
  minimum_sale_price: number | null;
  image_url: string | null;
  active: boolean;
  created_at: string;
};

export type Category = {
  id: string;
  name: string;
};

export type Supplier = {
  id: string;
  name: string;
  active: boolean;
};

export type SupplierPrice = {
  id: string;
  supplier_id: string;
  product_id: string;
  purchase_price: number;
  available: boolean;
  notes: string | null;
  last_checked_at: string;
};

type ProductForm = {
  name: string;
  sku: string;
  brand: string;
  category_id: string;
  unit: string;
  sale_price: string;
  minimum_sale_price: string;
  image_url: string;
};

const emptyForm: ProductForm = {
  name: "",
  sku: "",
  brand: "",
  category_id: "",
  unit: "piece",
  sale_price: "",
  minimum_sale_price: "",
  image_url: "",
};

export function ProductsClient({
  companyId,
  currency,
  initialProducts,
  initialCategories,
  suppliers,
  initialPrices,
  canCreate,
  canUpdate,
  canArchive,
  canViewCost,
}: {
  companyId: string;
  currency: string;
  initialProducts: Product[];
  initialCategories: Category[];
  suppliers: Supplier[];
  initialPrices: SupplierPrice[];
  canCreate: boolean;
  canUpdate: boolean;
  canArchive: boolean;
  canViewCost: boolean;
}) {
  const [supabase] = useState(() => createClient());
  const router = useRouter();

  const [products, setProducts] =
    useState(initialProducts);

  const [categories, setCategories] =
    useState(initialCategories);

  const [prices, setPrices] =
    useState(initialPrices);

  const [search, setSearch] = useState("");

  const [status, setStatus] = useState<
    "all" | "active" | "archived"
  >("all");

  const [open, setOpen] = useState(false);
  const [editing, setEditing] =
    useState<Product | null>(null);

  const [form, setForm] =
    useState<ProductForm>(emptyForm);

  const [priceForm, setPriceForm] =
    useState<Record<string, string>>({});

  const [available, setAvailable] =
    useState<Record<string, boolean>>({});

  const [priceNotes, setPriceNotes] =
    useState<Record<string, string>>({});

  const [message, setMessage] =
    useState("");

  const [saving, setSaving] =
    useState(false);

  const [busyId, setBusyId] =
    useState<string | null>(null);

  const priceMap = useMemo(() => {
    const map =
      new Map<string, SupplierPrice[]>();

    for (const price of prices) {
      map.set(price.product_id, [
        ...(map.get(price.product_id) ?? []),
        price,
      ]);
    }

    return map;
  }, [prices]);

  const filtered = useMemo(() => {
    const query =
      search.trim().toLowerCase();

    return products.filter((product) => {
      const searchMatches =
        !query ||
        [
          product.name,
          product.sku,
          product.brand,
        ].some((value) =>
          value
            ?.toLowerCase()
            .includes(query)
        );

      const statusMatches =
        status === "all" ||
        (status === "active"
          ? product.active
          : !product.active);

      return searchMatches && statusMatches;
    });
  }, [products, search, status]);

  function cheapest(product: Product) {
    if (!canViewCost) {
      return null;
    }

    const rows = (
      priceMap.get(product.id) ?? []
    ).filter((row) => row.available);

    if (!rows.length) {
      return null;
    }

    return rows.reduce((best, current) =>
      Number(best.purchase_price) <=
      Number(current.purchase_price)
        ? best
        : current
    );
  }

  function startAdd() {
    if (!canCreate) {
      return;
    }

    setEditing(null);
    setForm(emptyForm);
    setPriceForm({});
    setAvailable({});
    setPriceNotes({});
    setMessage("");
    setOpen(true);
  }

  function startEdit(product: Product) {
    if (!canUpdate) {
      return;
    }

    setEditing(product);

    setForm({
      name: product.name,
      sku: product.sku ?? "",
      brand: product.brand ?? "",
      category_id:
        product.category_id ?? "",
      unit: product.unit,
      sale_price:
        product.sale_price?.toString() ??
        "",
      minimum_sale_price:
        product.minimum_sale_price?.toString() ??
        "",
      image_url:
        product.image_url ?? "",
    });

    const nextPrices:
      Record<string, string> = {};

    const nextAvailable:
      Record<string, boolean> = {};

    const nextNotes:
      Record<string, string> = {};

    for (
      const price of
        priceMap.get(product.id) ?? []
    ) {
      nextPrices[price.supplier_id] =
        String(price.purchase_price);

      nextAvailable[price.supplier_id] =
        price.available;

      nextNotes[price.supplier_id] =
        price.notes ?? "";
    }

    setPriceForm(nextPrices);
    setAvailable(nextAvailable);
    setPriceNotes(nextNotes);
    setMessage("");
    setOpen(true);
  }

  async function addCategory() {
    if (!canCreate && !canUpdate) {
      return;
    }

    const name =
      window.prompt("اسم الفئة الجديدة");

    if (!name?.trim()) {
      return;
    }

    const { data, error } =
      await supabase
        .from("categories")
        .insert({
          company_id: companyId,
          name: name.trim(),
        })
        .select("id,name")
        .single();

    if (error) {
      window.alert(error.message);
      return;
    }

    const category =
      data as Category;

    setCategories((current) =>
      [...current, category].sort(
        (a, b) =>
          a.name.localeCompare(
            b.name,
            "ar"
          )
      )
    );
  }

  async function save(
    event: React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();
    setMessage("");

    if (editing && !canUpdate) {
      setMessage(
        "ما عندك صلاحية تعديل الأصناف."
      );
      return;
    }

    if (!editing && !canCreate) {
      setMessage(
        "ما عندك صلاحية إضافة صنف."
      );
      return;
    }

    if (!form.name.trim()) {
      setMessage("اسم الصنف مطلوب.");
      return;
    }

    const salePrice =
      form.sale_price
        ? Number(form.sale_price)
        : null;

    const minimumSalePrice =
      form.minimum_sale_price
        ? Number(
            form.minimum_sale_price
          )
        : null;

    if (
      salePrice != null &&
      (!Number.isFinite(salePrice) ||
        salePrice < 0)
    ) {
      setMessage(
        "سعر البيع غير صحيح."
      );
      return;
    }

    if (
      minimumSalePrice != null &&
      (!Number.isFinite(
        minimumSalePrice
      ) ||
        minimumSalePrice < 0)
    ) {
      setMessage(
        "أقل سعر بيع غير صحيح."
      );
      return;
    }

    if (
      salePrice != null &&
      minimumSalePrice != null &&
      minimumSalePrice > salePrice
    ) {
      setMessage(
        "أقل سعر بيع لا يمكن أن يكون أكبر من سعر البيع."
      );
      return;
    }

    const supplierPrices = canUpdate
      ? suppliers
          .filter(
            (supplier) =>
              priceForm[
                supplier.id
              ]?.trim()
          )
          .map((supplier) => {
            const purchasePrice =
              Number(
                priceForm[supplier.id]
              );

            if (
              !Number.isFinite(
                purchasePrice
              ) ||
              purchasePrice < 0
            ) {
              throw new Error(
                `سعر شراء ${supplier.name} غير صحيح.`
              );
            }

            return {
              supplier_id:
                supplier.id,
              purchase_price:
                purchasePrice,
              available:
                available[
                  supplier.id
                ] !== false,
              notes:
                priceNotes[
                  supplier.id
                ]?.trim() ||
                null,
            };
          })
      : [];

    setSaving(true);

    try {
      const { data: productId, error } =
        await supabase.rpc(
          "save_product_with_supplier_prices",
          {
            target_company:
              companyId,

            target_product:
              editing?.id ?? null,

            product_name:
              form.name.trim(),

            product_sku:
              form.sku.trim() ||
              null,

            product_brand:
              form.brand.trim() ||
              null,

            target_category:
              form.category_id ||
              null,

            product_unit:
              form.unit,

            product_sale_price:
              salePrice,

            product_minimum_sale_price:
              minimumSalePrice,

            product_image_url:
              form.image_url.trim() ||
              null,

            product_active:
              editing?.active ??
              true,

            supplier_prices_payload:
              supplierPrices,
          }
        );

      if (error) {
        setMessage(error.message);
        return;
      }

      const id =
        String(
          productId ||
            editing?.id ||
            ""
        );

      if (!id) {
        setMessage(
          "تم الحفظ لكن تعذر قراءة الصنف."
        );
        return;
      }

      const productResult =
        await supabase
          .from("products")
          .select(
            "id,category_id,sku,name,brand,unit,sale_price,minimum_sale_price,image_url,active,created_at"
          )
          .eq("company_id", companyId)
          .eq("id", id)
          .single();

      if (
        productResult.error ||
        !productResult.data
      ) {
        setMessage(
          productResult.error?.message ||
            "تعذر تحديث بيانات الصنف."
        );
        return;
      }

      const savedProduct =
        productResult.data as Product;

      setProducts((current) =>
        editing
          ? current.map((row) =>
              row.id === id
                ? savedProduct
                : row
            )
          : [
              savedProduct,
              ...current,
            ]
      );

      if (canViewCost) {
        const pricesResult =
          await supabase
            .from(
              "supplier_prices"
            )
            .select(
              "id,supplier_id,product_id,purchase_price,available,notes,last_checked_at"
            )
            .eq(
              "company_id",
              companyId
            )
            .eq(
              "product_id",
              id
            );

        if (!pricesResult.error) {
          const savedPrices =
            (pricesResult.data ??
              []) as SupplierPrice[];

          setPrices((current) => [
            ...current.filter(
              (row) =>
                row.product_id !== id
            ),
            ...savedPrices,
          ]);
        }
      }

      setOpen(false);
      router.refresh();
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "تعذر حفظ الصنف."
      );
    } finally {
      setSaving(false);
    }
  }

  async function toggleArchive(
    product: Product
  ) {
    if (!canArchive) {
      return;
    }

    const nextActive =
      !product.active;

    const confirmed =
      window.confirm(
        nextActive
          ? `إعادة تفعيل ${product.name}؟`
          : `أرشفة ${product.name}؟`
      );

    if (!confirmed) {
      return;
    }

    setBusyId(product.id);

    const { error } =
      await supabase.rpc(
        "set_product_active",
        {
          target_company:
            companyId,
          target_product:
            product.id,
          target_active:
            nextActive,
        }
      );

    setBusyId(null);

    if (error) {
      window.alert(error.message);
      return;
    }

    setProducts((current) =>
      current.map((row) =>
        row.id === product.id
          ? {
              ...row,
              active: nextActive,
            }
          : row
      )
    );

    router.refresh();
  }

  const activeCount =
    products.filter(
      (product) => product.active
    ).length;

  const archivedCount =
    products.length - activeCount;

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            الكتالوج
          </span>

          <h2>
            الأصناف والأسعار
          </h2>

          <p className="muted">
            إدارة الأصناف وأسعار
            البيع ومصادر الشراء.
          </p>
        </div>

        <div className="rowActions">
          {(canCreate ||
            canUpdate) && (
            <button
              type="button"
              className="softButton"
              onClick={() =>
                void addCategory()
              }
            >
              <Icons.plus size={14} />
              فئة
            </button>
          )}

          {canCreate && (
            <button
              type="button"
              className="primaryButton"
              onClick={startAdd}
            >
              <Icons.plus size={14} />
              إضافة صنف
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="كل الأصناف"
          value={String(
            products.length
          )}
        />

        <Mini
          title="نشط"
          value={String(
            activeCount
          )}
        />

        <Mini
          title="مؤرشف"
          value={String(
            archivedCount
          )}
        />

        <Mini
          title="بدون سعر بيع"
          value={String(
            products.filter(
              (product) =>
                product.sale_price ==
                null
            ).length
          )}
        />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        <div className="filters">
          <div className="searchBox">
            <Icons.search
              size={16}
            />

            <input
              value={search}
              onChange={(event) =>
                setSearch(
                  event.target.value
                )
              }
              placeholder="ابحث بالاسم، الكود أو الماركة..."
            />
          </div>

          <select
            value={status}
            onChange={(event) =>
              setStatus(
                event.target
                  .value as
                  | "all"
                  | "active"
                  | "archived"
              )
            }
          >
            <option value="all">
              كل الحالات
            </option>
            <option value="active">
              النشطة
            </option>
            <option value="archived">
              المؤرشفة
            </option>
          </select>

          <div />

          <div className="resultCount">
            {filtered.length} نتيجة
          </div>
        </div>

        {!filtered.length ? (
          <div className="empty">
            <Icons.box
              size={29}
            />

            <h3>
              ما في أصناف
            </h3>

            <p>
              ما في نتائج مطابقة.
            </p>
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>الصنف</th>
                  <th>سعر البيع</th>

                  {canViewCost && (
                    <>
                      <th>
                        أرخص شراء
                      </th>
                      <th>
                        الهامش
                      </th>
                      <th>
                        الموردون
                      </th>
                    </>
                  )}

                  <th>الحالة</th>
                  <th>إجراءات</th>
                </tr>
              </thead>

              <tbody>
                {filtered.map(
                  (product) => {
                    const cheapestPrice =
                      cheapest(product);

                    const margin =
                      canViewCost &&
                      product.sale_price !=
                        null &&
                      Number(
                        product.sale_price
                      ) > 0 &&
                      cheapestPrice
                        ? ((Number(
                            product.sale_price
                          ) -
                            Number(
                              cheapestPrice.purchase_price
                            )) /
                            Number(
                              product.sale_price
                            )) *
                          100
                        : null;

                    return (
                      <tr
                        key={
                          product.id
                        }
                      >
                        <td>
                          <div className="merchant">
                            <div className="merchantLogo">
                              {product.name.charAt(
                                0
                              )}
                            </div>

                            <div>
                              <strong>
                                {
                                  product.name
                                }
                              </strong>

                              <span>
                                {[
                                  product.brand,
                                  product.sku,
                                ]
                                  .filter(
                                    Boolean
                                  )
                                  .join(
                                    " • "
                                  ) ||
                                  "—"}
                              </span>
                            </div>
                          </div>
                        </td>

                        <td>
                          {product.sale_price !=
                          null
                            ? `${Number(
                                product.sale_price
                              ).toFixed(
                                2
                              )} ${currency}`
                            : "—"}
                        </td>

                        {canViewCost && (
                          <>
                            <td>
                              {cheapestPrice
                                ? `${Number(
                                    cheapestPrice.purchase_price
                                  ).toFixed(
                                    2
                                  )} ${currency}`
                                : "—"}
                            </td>

                            <td>
                              {margin !=
                              null ? (
                                <span
                                  className={`chip ${
                                    margin >=
                                    20
                                      ? "green"
                                      : margin >=
                                          10
                                        ? "orange"
                                        : "gray"
                                  }`}
                                >
                                  {margin.toFixed(
                                    1
                                  )}
                                  %
                                </span>
                              ) : (
                                "—"
                              )}
                            </td>

                            <td>
                              {
                                (
                                  priceMap.get(
                                    product.id
                                  ) ?? []
                                ).length
                              }
                            </td>
                          </>
                        )}

                        <td>
                          <span
                            className={`chip ${
                              product.active
                                ? "green"
                                : "gray"
                            }`}
                          >
                            {product.active
                              ? "نشط"
                              : "مؤرشف"}
                          </span>
                        </td>

                        <td>
                          <div className="rowActions">
                            <Link
                              className="softButton"
                              href={`/products/${product.id}`}
                            >
                              فتح
                            </Link>

                            {canUpdate && (
                              <button
                                type="button"
                                className="softButton"
                                onClick={() =>
                                  startEdit(
                                    product
                                  )
                                }
                              >
                                <Icons.edit
                                  size={13}
                                />
                              </button>
                            )}

                            {canArchive && (
                              <button
                                type="button"
                                className={
                                  product.active
                                    ? "dangerButton"
                                    : "softButton"
                                }
                                disabled={
                                  busyId ===
                                  product.id
                                }
                                onClick={() =>
                                  void toggleArchive(
                                    product
                                  )
                                }
                              >
                                {product.active
                                  ? "أرشفة"
                                  : "إعادة تفعيل"}
                              </button>
                            )}
                          </div>
                        </td>
                      </tr>
                    );
                  }
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {open && (
        <div
          className="modalOverlay"
          onMouseDown={(event) => {
            if (
              event.target ===
                event.currentTarget &&
              !saving
            ) {
              setOpen(false);
            }
          }}
        >
          <section
            className="modal"
            style={{
              maxWidth: 900,
              width: "94vw",
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  {editing
                    ? "تعديل صنف"
                    : "صنف جديد"}
                </span>

                <h2>
                  {editing?.name ||
                    "إضافة صنف"}
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setOpen(false)
                }
              >
                ×
              </button>
            </div>

            <form onSubmit={save}>
              <div className="formGrid">
                <Field
                  label="اسم الصنف *"
                  value={form.name}
                  onChange={(value) =>
                    setForm(
                      (current) => ({
                        ...current,
                        name: value,
                      })
                    )
                  }
                />

                <Field
                  label="SKU / الكود"
                  value={form.sku}
                  onChange={(value) =>
                    setForm(
                      (current) => ({
                        ...current,
                        sku: value,
                      })
                    )
                  }
                />

                <Field
                  label="الماركة"
                  value={form.brand}
                  onChange={(value) =>
                    setForm(
                      (current) => ({
                        ...current,
                        brand: value,
                      })
                    )
                  }
                />

                <label className="field">
                  <span>الفئة</span>

                  <select
                    value={
                      form.category_id
                    }
                    onChange={(event) =>
                      setForm(
                        (current) => ({
                          ...current,
                          category_id:
                            event.target
                              .value,
                        })
                      )
                    }
                  >
                    <option value="">
                      بدون فئة
                    </option>

                    {categories.map(
                      (category) => (
                        <option
                          key={
                            category.id
                          }
                          value={
                            category.id
                          }
                        >
                          {
                            category.name
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>الوحدة</span>

                  <select
                    value={form.unit}
                    onChange={(event) =>
                      setForm(
                        (current) => ({
                          ...current,
                          unit: event
                            .target
                            .value,
                        })
                      )
                    }
                  >
                    <option value="piece">
                      قطعة
                    </option>
                    <option value="box">
                      علبة
                    </option>
                    <option value="meter">
                      متر
                    </option>
                    <option value="roll">
                      رول
                    </option>
                    <option value="set">
                      طقم
                    </option>
                  </select>
                </label>

                <Field
                  label={`سعر البيع (${currency})`}
                  value={
                    form.sale_price
                  }
                  type="number"
                  onChange={(value) =>
                    setForm(
                      (current) => ({
                        ...current,
                        sale_price:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label={`أقل سعر بيع (${currency})`}
                  value={
                    form.minimum_sale_price
                  }
                  type="number"
                  onChange={(value) =>
                    setForm(
                      (current) => ({
                        ...current,
                        minimum_sale_price:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="رابط صورة المنتج"
                  value={
                    form.image_url
                  }
                  onChange={(value) =>
                    setForm(
                      (current) => ({
                        ...current,
                        image_url:
                          value,
                      })
                    )
                  }
                />
              </div>

              {canUpdate && (
                <div
                  className="panel panelPad"
                  style={{
                    marginTop: 15,
                  }}
                >
                  <div className="panelHeader">
                    <div>
                      <h2>
                        أسعار الموردين
                      </h2>

                      <p>
                        أي تعديل بالسعر
                        ينحفظ بالسجل
                        التاريخي.
                      </p>
                    </div>
                  </div>

                  {!suppliers.length ? (
                    <p className="muted">
                      ما في موردين نشطين.
                    </p>
                  ) : (
                    <div className="formGrid">
                      {suppliers.map(
                        (supplier) => (
                          <div
                            className="field"
                            key={
                              supplier.id
                            }
                          >
                            <span>
                              {
                                supplier.name
                              }
                            </span>

                            <input
                              type="number"
                              min="0"
                              step="0.01"
                              placeholder={`سعر الشراء ${currency}`}
                              value={
                                priceForm[
                                  supplier.id
                                ] ?? ""
                              }
                              onChange={(
                                event
                              ) =>
                                setPriceForm(
                                  (
                                    current
                                  ) => ({
                                    ...current,
                                    [supplier.id]:
                                      event
                                        .target
                                        .value,
                                  })
                                )
                              }
                            />

                            <input
                              placeholder="ملاحظات السعر"
                              value={
                                priceNotes[
                                  supplier.id
                                ] ?? ""
                              }
                              onChange={(
                                event
                              ) =>
                                setPriceNotes(
                                  (
                                    current
                                  ) => ({
                                    ...current,
                                    [supplier.id]:
                                      event
                                        .target
                                        .value,
                                  })
                                )
                              }
                            />

                            <label
                              style={{
                                display:
                                  "flex",
                                gap: 7,
                                alignItems:
                                  "center",
                              }}
                            >
                              <input
                                type="checkbox"
                                checked={
                                  available[
                                    supplier.id
                                  ] !== false
                                }
                                onChange={(
                                  event
                                ) =>
                                  setAvailable(
                                    (
                                      current
                                    ) => ({
                                      ...current,
                                      [supplier.id]:
                                        event
                                          .target
                                          .checked,
                                    })
                                  )
                                }
                              />

                              متوفر
                            </label>
                          </div>
                        )
                      )}
                    </div>
                  )}
                </div>
              )}

              {message && (
                <div
                  className="toastError"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {message}
                </div>
              )}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={saving}
                  onClick={() =>
                    setOpen(false)
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={saving}
                >
                  {saving
                    ? "عم نحفظ..."
                    : "حفظ الصنف"}
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
  onChange,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: "text" | "number";
}) {
  return (
    <label className="field">
      <span>{label}</span>

      <input
        type={type}
        min={
          type === "number"
            ? "0"
            : undefined
        }
        step={
          type === "number"
            ? "0.01"
            : undefined
        }
        value={value}
        onChange={(event) =>
          onChange(
            event.target.value
          )
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
      <div className="statLabel">
        {title}
      </div>

      <div className="statValue">
        {value}
      </div>
    </div>
  );
}
