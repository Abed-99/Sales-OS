"use client";

import Link from "next/link";
import {
  useEffect,
  useMemo,
  useState,
} from "react";
import type {
  FormEvent,
} from "react";
import {
  useRouter,
  useSearchParams,
} from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

export type Product = {
  id: string;
  category_id:
    | string
    | null;
  sku: string | null;
  name: string;
  brand: string | null;
  unit: string;
  sale_price:
    | number
    | null;
  minimum_sale_price:
    | number
    | null;
  image_url:
    | string
    | null;
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

type ProductFilter =
  | "all"
  | "active"
  | "archived";

type Stats = {
  all: number;
  active: number;
  archived: number;
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

function emptyForm():
  ProductForm {
  return {
    name: "",
    sku: "",
    brand: "",
    category_id: "",
    unit: "piece",
    sale_price: "",
    minimum_sale_price:
      "",
    image_url: "",
  };
}

function validHttpUrl(
  value: string
) {
  if (!value.trim()) {
    return true;
  }

  try {
    const url =
      new URL(
        value.trim()
      );

    return (
      url.protocol ===
        "http:" ||
      url.protocol ===
        "https:"
    );
  } catch {
    return false;
  }
}

function friendlyError(
  error:
    | {
        code?: string;
        message?: string;
      }
    | null,
  action:
    | "save"
    | "archive"
    | "category"
) {
  const message =
    error?.message?.toLowerCase() ??
    "";

  if (
    error?.code ===
      "42501" ||
    message.includes(
      "not allowed"
    ) ||
    message.includes(
      "permission"
    )
  ) {
    return "ما عندك صلاحية لتنفيذ هذه العملية.";
  }

  if (
    error?.code ===
      "23505" ||
    message.includes(
      "duplicate"
    )
  ) {
    return action ===
      "category"
      ? "هذه الفئة موجودة مسبقاً."
      : "كود الصنف مستخدم مسبقاً.";
  }

  if (
    message.includes(
      "category does not belong"
    )
  ) {
    return "الفئة المختارة غير صالحة لهذه الشركة.";
  }

  if (
    action ===
    "archive"
  ) {
    return "تعذر تغيير حالة الصنف. حاول مرة ثانية.";
  }

  if (
    action ===
    "category"
  ) {
    return "تعذر إضافة الفئة. حاول مرة ثانية.";
  }

  return "تعذر حفظ الصنف. تحقق من البيانات وحاول مرة ثانية.";
}

export function ProductsClient({
  companyId,
  currency,
  initialProducts,
  initialCategories,
  suppliers,
  initialPrices,
  initialError,
  stats,
  totalCount,
  page,
  pageSize,
  searchQuery,
  statusFilter,
  categoryFilter,
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
  initialError:
    | string
    | null;
  stats: Stats | null;
  totalCount: number;
  page: number;
  pageSize: number;
  searchQuery: string;
  statusFilter: ProductFilter;
  categoryFilter: string;
  canCreate: boolean;
  canUpdate: boolean;
  canArchive: boolean;
  canViewCost: boolean;
}) {
  const [supabase] =
    useState(
      () =>
        createClient()
    );

  const router =
    useRouter();

  const searchParams =
    useSearchParams();

  const [
    products,
    setProducts,
  ] =
    useState(
      initialProducts
    );

  const [
    categories,
    setCategories,
  ] =
    useState(
      initialCategories
    );

  const [
    prices,
    setPrices,
  ] =
    useState(
      initialPrices
    );

  const [
    search,
    setSearch,
  ] =
    useState(
      searchQuery
    );

  const [
    status,
    setStatus,
  ] =
    useState<ProductFilter>(
      statusFilter
    );

  const [
    category,
    setCategory,
  ] =
    useState(
      categoryFilter
    );

  const [
    open,
    setOpen,
  ] =
    useState(false);

  const [
    editing,
    setEditing,
  ] =
    useState<Product | null>(
      null
    );

  const [
    form,
    setForm,
  ] =
    useState<ProductForm>(
      emptyForm
    );

  const [
    priceForm,
    setPriceForm,
  ] =
    useState<
      Record<
        string,
        string
      >
    >({});

  const [
    available,
    setAvailable,
  ] =
    useState<
      Record<
        string,
        boolean
      >
    >({});

  const [
    priceNotes,
    setPriceNotes,
  ] =
    useState<
      Record<
        string,
        string
      >
    >({});

  const [
    newCategory,
    setNewCategory,
  ] =
    useState("");

  const [
    formMessage,
    setFormMessage,
  ] =
    useState("");

  const [
    pageMessage,
    setPageMessage,
  ] =
    useState(
      initialError ?? ""
    );

  const [
    saving,
    setSaving,
  ] =
    useState(false);

  const [
    categorySaving,
    setCategorySaving,
  ] =
    useState(false);

  const [
    busyId,
    setBusyId,
  ] =
    useState<string | null>(
      null
    );

  useEffect(() => {
    setProducts(
      initialProducts
    );
  }, [initialProducts]);

  useEffect(() => {
    setCategories(
      initialCategories
    );
  }, [initialCategories]);

  useEffect(() => {
    setPrices(
      initialPrices
    );
  }, [initialPrices]);

  useEffect(() => {
    setSearch(
      searchQuery
    );
  }, [searchQuery]);

  useEffect(() => {
    setStatus(
      statusFilter
    );
  }, [statusFilter]);

  useEffect(() => {
    setCategory(
      categoryFilter
    );
  }, [categoryFilter]);

  useEffect(() => {
    setPageMessage(
      initialError ?? ""
    );
  }, [initialError]);

  const pageCount =
    Math.max(
      1,
      Math.ceil(
        totalCount /
          pageSize
      )
    );

  const visibleFrom =
    totalCount === 0
      ? 0
      : (page - 1) *
          pageSize +
        1;

  const visibleTo =
    Math.min(
      page *
        pageSize,
      totalCount
    );

  const categoryNames =
    useMemo(
      () =>
        new Map(
          categories.map(
            (row) => [
              row.id,
              row.name,
            ]
          )
        ),
      [categories]
    );

  const supplierNames =
    useMemo(
      () =>
        new Map(
          suppliers.map(
            (row) => [
              row.id,
              row.name,
            ]
          )
        ),
      [suppliers]
    );

  const priceMap =
    useMemo(() => {
      const map =
        new Map<
          string,
          SupplierPrice[]
        >();

      for (
        const price of
        prices
      ) {
        map.set(
          price.product_id,
          [
            ...(map.get(
              price.product_id
            ) ?? []),
            price,
          ]
        );
      }

      return map;
    }, [prices]);

  function cheapest(
    product: Product
  ) {
    if (
      !canViewCost
    ) {
      return null;
    }

    const rows =
      (
        priceMap.get(
          product.id
        ) ?? []
      ).filter(
        (row) =>
          row.available
      );

    if (!rows.length) {
      return null;
    }

    return rows.reduce(
      (
        best,
        current
      ) =>
        Number(
          best.purchase_price
        ) <=
        Number(
          current.purchase_price
        )
          ? best
          : current
    );
  }

  function navigate(
    nextSearch: string,
    nextStatus:
      ProductFilter,
    nextCategory: string,
    nextPage = 1
  ) {
    const params =
      new URLSearchParams(
        searchParams.toString()
      );

    const clean =
      nextSearch.trim();

    if (clean) {
      params.set(
        "q",
        clean
      );
    } else {
      params.delete("q");
    }

    if (
      nextStatus !==
      "all"
    ) {
      params.set(
        "status",
        nextStatus
      );
    } else {
      params.delete(
        "status"
      );
    }

    if (nextCategory) {
      params.set(
        "category",
        nextCategory
      );
    } else {
      params.delete(
        "category"
      );
    }

    if (nextPage > 1) {
      params.set(
        "page",
        String(nextPage)
      );
    } else {
      params.delete(
        "page"
      );
    }

    const query =
      params.toString();

    router.push(
      query
        ? `/products?${query}`
        : "/products"
    );
  }

  function submitSearch(
    event: FormEvent
  ) {
    event.preventDefault();

    navigate(
      search,
      status,
      category,
      1
    );
  }

  function startAdd() {
    if (!canCreate) {
      return;
    }

    setEditing(null);

    setForm(
      emptyForm()
    );

    setPriceForm({});
    setAvailable({});
    setPriceNotes({});
    setNewCategory("");
    setFormMessage("");
    setOpen(true);
  }

  function startEdit(
    product: Product
  ) {
    if (!canUpdate) {
      return;
    }

    setEditing(
      product
    );

    setForm({
      name:
        product.name,

      sku:
        product.sku ??
        "",

      brand:
        product.brand ??
        "",

      category_id:
        product.category_id ??
        "",

      unit:
        product.unit,

      sale_price:
        product.sale_price ==
        null
          ? ""
          : String(
              product.sale_price
            ),

      minimum_sale_price:
        product.minimum_sale_price ==
        null
          ? ""
          : String(
              product.minimum_sale_price
            ),

      image_url:
        product.image_url ??
        "",
    });

    const nextPrices:
      Record<
        string,
        string
      > = {};

    const nextAvailable:
      Record<
        string,
        boolean
      > = {};

    const nextNotes:
      Record<
        string,
        string
      > = {};

    for (
      const price of
        priceMap.get(
          product.id
        ) ?? []
    ) {
      nextPrices[
        price.supplier_id
      ] =
        String(
          price.purchase_price
        );

      nextAvailable[
        price.supplier_id
      ] =
        price.available;

      nextNotes[
        price.supplier_id
      ] =
        price.notes ?? "";
    }

    setPriceForm(
      nextPrices
    );

    setAvailable(
      nextAvailable
    );

    setPriceNotes(
      nextNotes
    );

    setNewCategory("");
    setFormMessage("");
    setOpen(true);
  }

  async function addCategory() {
    if (!canCreate) {
      setFormMessage(
        "ما عندك صلاحية إضافة فئة."
      );
      return;
    }

    const name =
      newCategory
        .trim();

    if (!name) {
      setFormMessage(
        "اكتب اسم الفئة أولاً."
      );
      return;
    }

    if (
      name.length >
      120
    ) {
      setFormMessage(
        "اسم الفئة طويل جداً."
      );
      return;
    }

    setCategorySaving(
      true
    );

    try {
      const {
        data,
        error,
      } =
        await supabase
          .from(
            "categories"
          )
          .insert({
            company_id:
              companyId,
            name,
          })
          .select(
            "id,name"
          )
          .single();

      if (error) {
        setFormMessage(
          friendlyError(
            error,
            "category"
          )
        );
        return;
      }

      const row =
        data as Category;

      setCategories(
        (current) =>
          [
            ...current,
            row,
          ].sort(
            (a, b) =>
              a.name.localeCompare(
                b.name,
                "ar"
              )
          )
      );

      setForm(
        (current) => ({
          ...current,
          category_id:
            row.id,
        })
      );

      setNewCategory("");
      setFormMessage("");
    } finally {
      setCategorySaving(
        false
      );
    }
  }

  async function save(
    event: FormEvent
  ) {
    event.preventDefault();
    setFormMessage("");

    if (
      editing &&
      !canUpdate
    ) {
      setFormMessage(
        "ما عندك صلاحية تعديل الصنف."
      );
      return;
    }

    if (
      !editing &&
      !canCreate
    ) {
      setFormMessage(
        "ما عندك صلاحية إضافة صنف."
      );
      return;
    }

    const name =
      form.name.trim();

    if (!name) {
      setFormMessage(
        "اسم الصنف مطلوب."
      );
      return;
    }

    if (
      name.length > 200
    ) {
      setFormMessage(
        "اسم الصنف طويل جداً."
      );
      return;
    }

    const unit =
      form.unit.trim();

    if (!unit) {
      setFormMessage(
        "وحدة القياس مطلوبة."
      );
      return;
    }

    const salePrice =
      form.sale_price.trim() ===
      ""
        ? null
        : Number(
            form.sale_price
          );

    const minimumSalePrice =
      form.minimum_sale_price.trim() ===
      ""
        ? null
        : Number(
            form.minimum_sale_price
          );

    if (
      salePrice !== null &&
      (
        !Number.isFinite(
          salePrice
        ) ||
        salePrice < 0
      )
    ) {
      setFormMessage(
        "سعر البيع غير صحيح."
      );
      return;
    }

    if (
      minimumSalePrice !==
        null &&
      (
        !Number.isFinite(
          minimumSalePrice
        ) ||
        minimumSalePrice <
          0
      )
    ) {
      setFormMessage(
        "أقل سعر بيع غير صحيح."
      );
      return;
    }

    if (
      salePrice !== null &&
      minimumSalePrice !==
        null &&
      minimumSalePrice >
        salePrice
    ) {
      setFormMessage(
        "أقل سعر بيع لا يمكن أن يكون أكبر من سعر البيع."
      );
      return;
    }

    if (
      !validHttpUrl(
        form.image_url
      )
    ) {
      setFormMessage(
        "رابط صورة المنتج غير صحيح. استخدم رابط http أو https."
      );
      return;
    }

    const supplierPrices:
      Array<{
        supplier_id: string;
        purchase_price: number;
        available: boolean;
        notes:
          | string
          | null;
      }> = [];

    if (canUpdate) {
      for (
        const supplier of
          suppliers.filter(
            (row) =>
              row.active
          )
      ) {
        const raw =
          priceForm[
            supplier.id
          ]?.trim();

        if (!raw) {
          continue;
        }

        const value =
          Number(raw);

        if (
          !Number.isFinite(
            value
          ) ||
          value < 0
        ) {
          setFormMessage(
            `سعر شراء ${supplier.name} غير صحيح.`
          );
          return;
        }

        supplierPrices.push({
          supplier_id:
            supplier.id,

          purchase_price:
            value,

          available:
            available[
              supplier.id
            ] !== false,

          notes:
            priceNotes[
              supplier.id
            ]?.trim() ||
            null,
        });
      }
    }

    setSaving(true);

    try {
      const {
        error,
      } =
        await supabase.rpc(
          "save_product_with_supplier_prices",
          {
            target_company:
              companyId,

            target_product:
              editing?.id ??
              null,

            product_name:
              name,

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
              unit,

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
        setFormMessage(
          friendlyError(
            error,
            "save"
          )
        );
        return;
      }

      setOpen(false);
      setEditing(null);
      setForm(
        emptyForm()
      );
      setPageMessage("");
      router.refresh();
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
          : `أرشفة ${product.name}؟ لن يتم حذف تاريخ الصنف أو الحركات المرتبطة به.`
      );

    if (!confirmed) {
      return;
    }

    setBusyId(
      product.id
    );

    setPageMessage("");

    try {
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

      if (error) {
        setPageMessage(
          friendlyError(
            error,
            "archive"
          )
        );
        return;
      }

      setProducts(
        (current) =>
          current.map(
            (row) =>
              row.id ===
              product.id
                ? {
                    ...row,
                    active:
                      nextActive,
                  }
                : row
          )
      );

      router.refresh();
    } finally {
      setBusyId(null);
    }
  }

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
            إدارة الأصناف، أسعار البيع ومصادر الشراء.
          </p>
        </div>

        {canCreate ? (
          <button
            type="button"
            className="primaryButton"
            onClick={
              startAdd
            }
          >
            <Icons.plus
              size={14}
            />
            إضافة صنف
          </button>
        ) : null}
      </div>

      {pageMessage ? (
        <div
          className="toastError"
          role="alert"
          aria-live="polite"
          style={{
            marginBottom: 14,
          }}
        >
          {pageMessage}
        </div>
      ) : null}

      <section className="statsGrid">
        <Mini
          title="كل الأصناف"
          value={
            stats?.all ??
            "—"
          }
        />

        <Mini
          title="نشطة"
          value={
            stats?.active ??
            "—"
          }
        />

        <Mini
          title="مؤرشفة"
          value={
            stats?.archived ??
            "—"
          }
        />

        <Mini
          title="المعروض حالياً"
          value={
            totalCount
          }
        />
      </section>

      <section
        className="panel"
        style={{
          marginTop: 14,
        }}
      >
        <div className="filters">
          <form
            className="searchBox"
            onSubmit={
              submitSearch
            }
          >
            <Icons.search
              size={16}
            />

            <input
              value={search}
              onChange={(
                event
              ) =>
                setSearch(
                  event.target
                    .value
                )
              }
              placeholder="ابحث بالاسم، SKU أو الماركة..."
              aria-label="بحث في الأصناف"
            />

            <button
              type="submit"
              className="softButton"
            >
              بحث
            </button>
          </form>

          <select
            value={status}
            aria-label="حالة الصنف"
            onChange={(
              event
            ) => {
              const value =
                event.target
                  .value as ProductFilter;

              setStatus(
                value
              );

              navigate(
                search,
                value,
                category,
                1
              );
            }}
          >
            <option value="all">
              كل الحالات
            </option>

            <option value="active">
              نشط
            </option>

            <option value="archived">
              مؤرشف
            </option>
          </select>

          <select
            value={category}
            aria-label="فئة الصنف"
            onChange={(
              event
            ) => {
              const value =
                event.target
                  .value;

              setCategory(
                value
              );

              navigate(
                search,
                status,
                value,
                1
              );
            }}
          >
            <option value="">
              كل الفئات
            </option>

            {categories.map(
              (row) => (
                <option
                  key={
                    row.id
                  }
                  value={
                    row.id
                  }
                >
                  {row.name}
                </option>
              )
            )}
          </select>

          <div className="resultCount">
            {totalCount === 0
              ? "0 نتيجة"
              : `${visibleFrom}–${visibleTo} من ${totalCount}`}
          </div>
        </div>

        {!products.length ? (
          <div className="empty">
            <Icons.box
              size={29}
            />

            <h3>
              لا توجد أصناف
            </h3>

            <p>
              غيّر البحث أو التصفية وحاول مرة ثانية.
            </p>

            {canCreate &&
            !searchQuery &&
            statusFilter ===
              "all" &&
            !categoryFilter ? (
              <button
                type="button"
                className="primaryButton"
                onClick={
                  startAdd
                }
              >
                إضافة أول صنف
              </button>
            ) : null}
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>
                    الصنف
                  </th>
                  <th>
                    الفئة
                  </th>
                  <th>
                    الوحدة
                  </th>
                  <th>
                    سعر البيع
                  </th>

                  {canViewCost ? (
                    <th>
                      أرخص شراء
                    </th>
                  ) : null}

                  <th>
                    الحالة
                  </th>

                  <th>
                    إجراءات
                  </th>
                </tr>
              </thead>

              <tbody>
                {products.map(
                  (product) => {
                    const cheap =
                      cheapest(
                        product
                      );

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
                                  product.sku,
                                  product.brand,
                                ]
                                  .filter(
                                    Boolean
                                  )
                                  .join(
                                    " • "
                                  ) ||
                                  "بدون كود أو ماركة"}
                              </span>
                            </div>
                          </div>
                        </td>

                        <td>
                          {product.category_id
                            ? categoryNames.get(
                                product.category_id
                              ) ||
                              "—"
                            : "—"}
                        </td>

                        <td>
                          {
                            product.unit
                          }
                        </td>

                        <td>
                          {product.sale_price ==
                          null
                            ? "—"
                            : `${Number(
                                product.sale_price
                              ).toFixed(
                                2
                              )} ${currency}`}
                        </td>

                        {canViewCost ? (
                          <td>
                            {cheap
                              ? `${Number(
                                  cheap.purchase_price
                                ).toFixed(
                                  2
                                )} ${currency}`
                              : "—"}

                            {cheap ? (
                              <div className="muted">
                                {supplierNames.get(
                                  cheap.supplier_id
                                ) ||
                                  "مورد"}
                              </div>
                            ) : null}
                          </td>
                        ) : null}

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

                            {canUpdate ? (
                              <button
                                type="button"
                                className="softButton"
                                aria-label={`تعديل ${product.name}`}
                                title="تعديل"
                                onClick={() =>
                                  startEdit(
                                    product
                                  )
                                }
                              >
                                <Icons.edit
                                  size={
                                    13
                                  }
                                />
                              </button>
                            ) : null}

                            {canArchive ? (
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
                                  toggleArchive(
                                    product
                                  )
                                }
                              >
                                {product.active
                                  ? "أرشفة"
                                  : "تفعيل"}
                              </button>
                            ) : null}
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

        {pageCount > 1 ? (
          <div
            className="rowActions"
            style={{
              justifyContent:
                "center",
              padding: 16,
            }}
          >
            <button
              type="button"
              className="softButton"
              disabled={
                page <= 1
              }
              onClick={() =>
                navigate(
                  searchQuery,
                  statusFilter,
                  categoryFilter,
                  Math.max(
                    1,
                    page - 1
                  )
                )
              }
            >
              السابق
            </button>

            <span className="muted">
              صفحة {page} من{" "}
              {pageCount}
            </span>

            <button
              type="button"
              className="softButton"
              disabled={
                page >=
                pageCount
              }
              onClick={() =>
                navigate(
                  searchQuery,
                  statusFilter,
                  categoryFilter,
                  Math.min(
                    pageCount,
                    page + 1
                  )
                )
              }
            >
              التالي
            </button>
          </div>
        ) : null}
      </section>

      {open ? (
        <div
          className="modalOverlay"
          onMouseDown={(
            event
          ) => {
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
            role="dialog"
            aria-modal="true"
            aria-labelledby="product-modal-title"
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  {editing
                    ? "تعديل الصنف"
                    : "صنف جديد"}
                </span>

                <h2 id="product-modal-title">
                  {editing
                    ? editing.name
                    : "إضافة صنف"}
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                aria-label="إغلاق"
                disabled={
                  saving
                }
                onClick={() =>
                  setOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={save}
            >
              <div className="formGrid">
                <Field
                  label="اسم الصنف *"
                  value={
                    form.name
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        name: value,
                      })
                    )
                  }
                />

                <Field
                  label="SKU / الكود"
                  value={
                    form.sku
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        sku: value,
                      })
                    )
                  }
                />

                <Field
                  label="الماركة"
                  value={
                    form.brand
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        brand:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="الوحدة"
                  value={
                    form.unit
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        unit: value,
                      })
                    )
                  }
                />

                <label className="field">
                  <span>
                    الفئة
                  </span>

                  <select
                    value={
                      form.category_id
                    }
                    onChange={(
                      event
                    ) =>
                      setForm(
                        (
                          current
                        ) => ({
                          ...current,
                          category_id:
                            event
                              .target
                              .value,
                        })
                      )
                    }
                  >
                    <option value="">
                      بدون فئة
                    </option>

                    {categories.map(
                      (row) => (
                        <option
                          key={
                            row.id
                          }
                          value={
                            row.id
                          }
                        >
                          {
                            row.name
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                {canCreate ? (
                  <div className="field">
                    <span>
                      فئة جديدة
                    </span>

                    <div className="rowActions">
                      <input
                        value={
                          newCategory
                        }
                        placeholder="اسم الفئة"
                        onChange={(
                          event
                        ) =>
                          setNewCategory(
                            event
                              .target
                              .value
                          )
                        }
                      />

                      <button
                        type="button"
                        className="softButton"
                        disabled={
                          categorySaving
                        }
                        onClick={() =>
                          void addCategory()
                        }
                      >
                        إضافة
                      </button>
                    </div>
                  </div>
                ) : null}

                <label className="field">
                  <span>
                    سعر البيع
                  </span>

                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={
                      form.sale_price
                    }
                    onChange={(
                      event
                    ) =>
                      setForm(
                        (
                          current
                        ) => ({
                          ...current,
                          sale_price:
                            event
                              .target
                              .value,
                        })
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    أقل سعر بيع
                  </span>

                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={
                      form.minimum_sale_price
                    }
                    onChange={(
                      event
                    ) =>
                      setForm(
                        (
                          current
                        ) => ({
                          ...current,
                          minimum_sale_price:
                            event
                              .target
                              .value,
                        })
                      )
                    }
                  />
                </label>

                <Field
                  label="رابط صورة المنتج"
                  value={
                    form.image_url
                  }
                  full
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        image_url:
                          value,
                      })
                    )
                  }
                />
              </div>

              {canUpdate &&
              suppliers.some(
                (row) =>
                  row.active
              ) ? (
                <div
                  style={{
                    marginTop: 20,
                  }}
                >
                  <div className="panelHeader">
                    <div>
                      <h3>
                        أسعار الموردين
                      </h3>

                      <p>
                        الأسعار الفارغة لن تُحفظ كمصدر شراء نشط.
                      </p>
                    </div>
                  </div>

                  <div className="quickList">
                    {suppliers
                      .filter(
                        (row) =>
                          row.active
                      )
                      .map(
                        (
                          supplier
                        ) => (
                          <div
                            className="quickItem"
                            key={
                              supplier.id
                            }
                          >
                            <div>
                              <strong>
                                {
                                  supplier.name
                                }
                              </strong>

                              <input
                                type="number"
                                min="0"
                                step="0.01"
                                placeholder="سعر الشراء"
                                value={
                                  priceForm[
                                    supplier.id
                                  ] ??
                                  ""
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
                            </div>

                            <div>
                              <label>
                                <input
                                  type="checkbox"
                                  checked={
                                    available[
                                      supplier.id
                                    ] !==
                                    false
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

                              <input
                                value={
                                  priceNotes[
                                    supplier.id
                                  ] ??
                                  ""
                                }
                                placeholder="ملاحظة"
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
                            </div>
                          </div>
                        )
                      )}
                  </div>
                </div>
              ) : null}

              {formMessage ? (
                <div
                  className="toastError"
                  role="alert"
                  aria-live="polite"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {formMessage}
                </div>
              ) : null}

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  disabled={
                    saving
                  }
                  onClick={() =>
                    setOpen(
                      false
                    )
                  }
                >
                  إلغاء
                </button>

                <button
                  className="primaryButton"
                  disabled={
                    saving
                  }
                >
                  {saving
                    ? "جارٍ الحفظ..."
                    : editing
                      ? "حفظ التعديلات"
                      : "إضافة الصنف"}
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
  onChange,
  full = false,
}: {
  label: string;
  value: string;
  onChange:
    (value: string) => void;
  full?: boolean;
}) {
  return (
    <label
      className={`field ${
        full ? "full" : ""
      }`}
    >
      <span>
        {label}
      </span>

      <input
        value={value}
        onChange={(
          event
        ) =>
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
  value:
    | number
    | string;
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