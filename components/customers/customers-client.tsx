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
import {
  normalizeSyrianMobile,
  syrianPhoneState,
} from "@/lib/phone";

type Status =
  | "new"
  | "contacted"
  | "interested"
  | "customer"
  | "inactive";

export type Trader = {
  id: string;
  name: string;
  contact_name: string | null;
  phone: string | null;
  whatsapp: string | null;
  area: string | null;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  status: Status;
  notes: string | null;
  whatsapp_marketing_opt_in: boolean;
  credit_limit: number | null;
  payment_terms_days: number;
  created_at: string;
  updated_at: string;
};

type Stats = {
  all: number;
  customers: number;
  interested: number;
  new: number;
};

const labels: Record<
  Status,
  string
> = {
  new: "جديد",
  contacted: "تم التواصل",
  interested: "مهتم",
  customer: "عميل",
  inactive: "مؤرشف",
};

function emptyForm() {
  return {
    name: "",
    contact_name: "",
    phone: "",
    whatsapp: "",
    area: "",
    address: "",
    latitude: "",
    longitude: "",
    status: "new" as Status,
    notes: "",
    optin: false,
    credit_limit: "",
    payment_terms_days: "0",
  };
}

function friendlyDbError(
  error:
    | {
        code?: string;
        message?: string;
      }
    | null,
  action: "save" | "archive"
) {
  const message =
    error?.message?.toLowerCase() ??
    "";

  if (
    error?.code === "23505" ||
    message.includes(
      "مستخدم عند تاجر"
    ) ||
    message.includes("duplicate")
  ) {
    return "رقم الهاتف أو واتساب مستخدم عند عميل آخر.";
  }

  if (
    error?.code === "42501" ||
    message.includes(
      "not allowed"
    ) ||
    message.includes(
      "permission"
    )
  ) {
    return "ما عندك صلاحية لتنفيذ هذه العملية.";
  }

  if (action === "archive") {
    return "تعذر أرشفة العميل. حاول مرة ثانية.";
  }

  return "تعذر حفظ بيانات العميل. تحقق من البيانات وحاول مرة ثانية.";
}

function statusClass(
  status: Status
) {
  if (status === "customer") {
    return "green";
  }

  if (status === "interested") {
    return "orange";
  }

  if (status === "inactive") {
    return "gray";
  }

  return "blue";
}

export function CustomersClient({
  companyId,
  currency,
  initialTraders,
  initialError,
  stats,
  totalCount,
  page,
  pageSize,
  searchQuery,
  statusFilter,
  canCreate,
  canUpdate,
  canArchive,
  canViewMap,
  canViewBalance,
}: {
  companyId: string;
  currency: string;
  initialTraders: Trader[];
  initialError: string | null;
  stats: Stats | null;
  totalCount: number;
  page: number;
  pageSize: number;
  searchQuery: string;
  statusFilter: Status | "all";
  canCreate: boolean;
  canUpdate: boolean;
  canArchive: boolean;
  canViewMap: boolean;
  canViewBalance: boolean;
}) {
  const [supabase] =
    useState(() => createClient());

  const router = useRouter();
  const searchParams =
    useSearchParams();

  const [rows, setRows] =
    useState(initialTraders);

  const [search, setSearch] =
    useState(searchQuery);

  const [status, setStatus] =
    useState<Status | "all">(
      statusFilter
    );

  const [open, setOpen] =
    useState(false);

  const [
    editing,
    setEditing,
  ] = useState<Trader | null>(
    null
  );

  const [form, setForm] =
    useState(emptyForm);

  const [
    formMessage,
    setFormMessage,
  ] = useState("");

  const [
    pageMessage,
    setPageMessage,
  ] = useState(
    initialError ?? ""
  );

  const [saving, setSaving] =
    useState(false);

  const [
    archivingId,
    setArchivingId,
  ] = useState<string | null>(
    null
  );

  useEffect(() => {
    setRows(initialTraders);
  }, [initialTraders]);

  useEffect(() => {
    setSearch(searchQuery);
  }, [searchQuery]);

  useEffect(() => {
    setStatus(statusFilter);
  }, [statusFilter]);

  useEffect(() => {
    setPageMessage(
      initialError ?? ""
    );
  }, [initialError]);

  const pageCount =
    Math.max(
      1,
      Math.ceil(
        totalCount / pageSize
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
      page * pageSize,
      totalCount
    );

  const statusOptions =
    useMemo(
      () =>
        (
          Object.entries(
            labels
          ) as [
            Status,
            string,
          ][]
        ).filter(
          ([key]) =>
            key !== "inactive" ||
            canArchive ||
            editing?.status ===
              "inactive"
        ),
      [
        canArchive,
        editing?.status,
      ]
    );

  function navigateFilters(
    nextSearch: string,
    nextStatus:
      | Status
      | "all",
    nextPage = 1
  ) {
    const params =
      new URLSearchParams(
        searchParams.toString()
      );

    const cleanedSearch =
      nextSearch.trim();

    if (cleanedSearch) {
      params.set(
        "q",
        cleanedSearch
      );
    } else {
      params.delete("q");
    }

    if (
      nextStatus !== "all"
    ) {
      params.set(
        "status",
        nextStatus
      );
    } else {
      params.delete("status");
    }

    if (nextPage > 1) {
      params.set(
        "page",
        String(nextPage)
      );
    } else {
      params.delete("page");
    }

    const query =
      params.toString();

    router.push(
      query
        ? `/customers?${query}`
        : "/customers"
    );
  }

  function submitSearch(
    event: FormEvent
  ) {
    event.preventDefault();

    navigateFilters(
      search,
      status,
      1
    );
  }

  function startAdd() {
    if (!canCreate) {
      return;
    }

    setEditing(null);
    setForm(emptyForm());
    setFormMessage("");
    setOpen(true);
  }

  function startEdit(
    trader: Trader
  ) {
    if (!canUpdate) {
      return;
    }

    setEditing(trader);

    setForm({
      name: trader.name,

      contact_name:
        trader.contact_name ??
        "",

      phone:
        trader.phone ?? "",

      whatsapp:
        trader.whatsapp ?? "",

      area:
        trader.area ?? "",

      address:
        trader.address ?? "",

      latitude:
        trader.latitude != null
          ? String(
              trader.latitude
            )
          : "",

      longitude:
        trader.longitude !=
        null
          ? String(
              trader.longitude
            )
          : "",

      status: trader.status,

      notes:
        trader.notes ?? "",

      optin:
        trader.whatsapp_marketing_opt_in,

      credit_limit:
        trader.credit_limit ==
        null
          ? ""
          : String(
              trader.credit_limit
            ),

      payment_terms_days:
        String(
          trader.payment_terms_days ??
            0
        ),
    });

    setFormMessage("");
    setOpen(true);
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
        "ما عندك صلاحية تعديل العميل."
      );
      return;
    }

    if (
      !editing &&
      !canCreate
    ) {
      setFormMessage(
        "ما عندك صلاحية إضافة عميل."
      );
      return;
    }

    const name =
      form.name.trim();

    if (!name) {
      setFormMessage(
        "اسم العميل أو المحل مطلوب."
      );
      return;
    }

    if (name.length > 200) {
      setFormMessage(
        "اسم العميل طويل جداً."
      );
      return;
    }

    if (
      form.status ===
        "inactive" &&
      editing?.status !==
        "inactive" &&
      !canArchive
    ) {
      setFormMessage(
        "ما عندك صلاحية أرشفة العميل."
      );
      return;
    }

    const phone =
      form.phone.trim()
        ? normalizeSyrianMobile(
            form.phone
          )
        : null;

    const whatsapp =
      form.whatsapp.trim()
        ? normalizeSyrianMobile(
            form.whatsapp
          )
        : null;

    if (
      form.phone.trim() &&
      !phone
    ) {
      setFormMessage(
        "رقم الهاتف السوري غير صحيح."
      );
      return;
    }

    if (
      form.whatsapp.trim() &&
      !whatsapp
    ) {
      setFormMessage(
        "رقم واتساب السوري غير صحيح."
      );
      return;
    }

    const duplicate =
      rows.find(
        (row) =>
          row.id !==
            editing?.id &&
          Boolean(
            (phone &&
              (row.phone ===
                phone ||
                row.whatsapp ===
                  phone)) ||
              (whatsapp &&
                (row.phone ===
                  whatsapp ||
                  row.whatsapp ===
                    whatsapp))
          )
      );

    if (duplicate) {
      setFormMessage(
        `الرقم مستخدم مسبقاً عند: ${duplicate.name}`
      );
      return;
    }

    const latitudeText =
      form.latitude.trim();

    const longitudeText =
      form.longitude.trim();

    if (
      Boolean(latitudeText) !==
      Boolean(longitudeText)
    ) {
      setFormMessage(
        "يجب إدخال Latitude و Longitude معاً."
      );
      return;
    }

    let latitude:
      | number
      | null = null;

    let longitude:
      | number
      | null = null;

    if (
      latitudeText &&
      longitudeText
    ) {
      latitude =
        Number(latitudeText);

      longitude =
        Number(longitudeText);

      if (
        !Number.isFinite(
          latitude
        ) ||
        latitude < -90 ||
        latitude > 90
      ) {
        setFormMessage(
          "Latitude يجب أن يكون بين -90 و 90."
        );
        return;
      }

      if (
        !Number.isFinite(
          longitude
        ) ||
        longitude < -180 ||
        longitude > 180
      ) {
        setFormMessage(
          "Longitude يجب أن يكون بين -180 و 180."
        );
        return;
      }
    }

    const payload:
      Record<
        string,
        unknown
      > = {
      company_id: companyId,

      name,

      contact_name:
        form.contact_name.trim() ||
        null,

      phone,

      whatsapp,

      area:
        form.area.trim() ||
        null,

      address:
        form.address.trim() ||
        null,

      latitude,

      longitude,

      status: form.status,

      notes:
        form.notes.trim() ||
        null,

      whatsapp_marketing_opt_in:
        form.optin,
    };

    if (canViewBalance) {
      const creditLimit =
        form.credit_limit.trim() ===
        ""
          ? null
          : Number(
              form.credit_limit
            );

      const paymentTerms =
        Number(
          form.payment_terms_days ||
            0
        );

      if (
        creditLimit !== null &&
        (!Number.isFinite(
          creditLimit
        ) ||
          creditLimit < 0)
      ) {
        setFormMessage(
          "حد الائتمان يجب أن يكون صفراً أو أكبر."
        );
        return;
      }

      if (
        !Number.isInteger(
          paymentTerms
        ) ||
        paymentTerms < 0 ||
        paymentTerms > 3650
      ) {
        setFormMessage(
          "مهلة الدفع يجب أن تكون بين 0 و 3650 يوماً."
        );
        return;
      }

      payload.credit_limit =
        creditLimit;

      payload.payment_terms_days =
        paymentTerms;
    }

    setSaving(true);

    try {
      if (editing) {
        const { error } =
          await supabase
            .from("traders")
            .update(payload)
            .eq(
              "company_id",
              companyId
            )
            .eq(
              "id",
              editing.id
            );

        if (error) {
          setFormMessage(
            friendlyDbError(
              error,
              "save"
            )
          );
          return;
        }
      } else {
        const { error } =
          await supabase
            .from("traders")
            .insert(payload);

        if (error) {
          setFormMessage(
            friendlyDbError(
              error,
              "save"
            )
          );
          return;
        }
      }

      setOpen(false);
      setEditing(null);
      setForm(emptyForm());
      setPageMessage("");
      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  async function archiveTrader(
    trader: Trader
  ) {
    if (
      !canArchive ||
      trader.status ===
        "inactive"
    ) {
      return;
    }

    if (
      !confirm(
        `أرشفة ${trader.name}؟ سيبقى السجل محفوظاً ويمكن إعادة تفعيله لاحقاً.`
      )
    ) {
      return;
    }

    setPageMessage("");
    setArchivingId(
      trader.id
    );

    try {
      const { error } =
        await supabase.rpc(
          "archive_trader",
          {
            target_company:
              companyId,

            target_trader:
              trader.id,
          }
        );

      if (error) {
        setPageMessage(
          friendlyDbError(
            error,
            "archive"
          )
        );
        return;
      }

      setRows((current) =>
        current.map((row) =>
          row.id === trader.id
            ? {
                ...row,
                status:
                  "inactive",
              }
            : row
        )
      );

      router.refresh();
    } finally {
      setArchivingId(
        null
      );
    }
  }

  function useLocation() {
    setFormMessage("");

    if (
      !navigator.geolocation
    ) {
      setFormMessage(
        "المتصفح لا يدعم تحديد الموقع."
      );
      return;
    }

    navigator.geolocation.getCurrentPosition(
      (position) => {
        setForm(
          (current) => ({
            ...current,

            latitude:
              position.coords.latitude.toFixed(
                7
              ),

            longitude:
              position.coords.longitude.toFixed(
                7
              ),
          })
        );
      },

      () => {
        setFormMessage(
          "تعذر الحصول على الموقع الحالي."
        );
      },

      {
        enableHighAccuracy:
          true,
        timeout: 8000,
      }
    );
  }

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            قاعدة السوق
          </span>

          <h2>
            العملاء والتجار
          </h2>

          <p className="muted">
            إدارة بيانات العملاء والتواصل والموقع وشروط الائتمان.
          </p>
        </div>

        {canCreate ? (
          <button
            className="primaryButton"
            onClick={startAdd}
          >
            <Icons.plus
              size={15}
            />
            إضافة عميل
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
          n={
            stats?.all ?? "—"
          }
          t="كل السجلات"
        />

        <Mini
          n={
            stats?.customers ??
            "—"
          }
          t="عملاء"
        />

        <Mini
          n={
            stats?.interested ??
            "—"
          }
          t="مهتمون"
        />

        <Mini
          n={
            stats?.new ?? "—"
          }
          t="جدد"
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
              placeholder="ابحث بالاسم، الرقم أو المنطقة..."
              aria-label="بحث في العملاء"
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
            aria-label="تصفية حسب الحالة"
            onChange={(
              event
            ) => {
              const value =
                event.target
                  .value as
                  | Status
                  | "all";

              setStatus(value);

              navigateFilters(
                search,
                value,
                1
              );
            }}
          >
            <option value="all">
              كل الحالات
            </option>

            {(
              Object.entries(
                labels
              ) as [
                Status,
                string,
              ][]
            ).map(
              ([
                key,
                value,
              ]) => (
                <option
                  key={key}
                  value={key}
                >
                  {value}
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

        {!rows.length ? (
          <div className="empty">
            <Icons.users
              size={29}
            />

            <h3>
              لا توجد نتائج
            </h3>

            <p>
              غيّر البحث أو حالة العميل وحاول مرة ثانية.
            </p>

            {canCreate &&
            !searchQuery &&
            statusFilter ===
              "all" ? (
              <button
                className="primaryButton"
                onClick={
                  startAdd
                }
              >
                إضافة أول عميل
              </button>
            ) : null}
          </div>
        ) : (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th>
                    العميل
                  </th>
                  <th>
                    المنطقة
                  </th>
                  <th>
                    الحالة
                  </th>

                  {canViewBalance ? (
                    <th>
                      الائتمان
                    </th>
                  ) : null}

                  <th>
                    واتساب
                  </th>

                  {canViewMap ? (
                    <th>
                      الموقع
                    </th>
                  ) : null}

                  <th>
                    إجراءات
                  </th>
                </tr>
              </thead>

              <tbody>
                {rows.map(
                  (trader) => (
                    <tr
                      key={
                        trader.id
                      }
                    >
                      <td>
                        <div className="merchant">
                          <div className="merchantLogo">
                            {trader.name.charAt(
                              0
                            )}
                          </div>

                          <div>
                            <strong>
                              {
                                trader.name
                              }
                            </strong>

                            <span>
                              {trader.contact_name ||
                                trader.phone ||
                                "بدون تفاصيل"}
                            </span>
                          </div>
                        </div>
                      </td>

                      <td>
                        {trader.area ||
                          "—"}
                      </td>

                      <td>
                        <span
                          className={`chip ${statusClass(
                            trader.status
                          )}`}
                        >
                          {
                            labels[
                              trader
                                .status
                            ]
                          }
                        </span>
                      </td>

                      {canViewBalance ? (
                        <td>
                          <strong>
                            {trader.credit_limit ==
                            null
                              ? "بدون حد"
                              : `${Number(
                                  trader.credit_limit
                                ).toFixed(
                                  2
                                )} ${currency}`}
                          </strong>

                          <span
                            className="muted"
                            style={{
                              display:
                                "block",
                            }}
                          >
                            {trader.payment_terms_days >
                            0
                              ? `${trader.payment_terms_days} يوم`
                              : "نقدي"}
                          </span>
                        </td>
                      ) : null}

                      <td>
                        {trader.whatsapp ? (
                          <a
                            className="softButton"
                            target="_blank"
                            rel="noreferrer"
                            href={`https://wa.me/${trader.whatsapp.replace(
                              /\D/g,
                              ""
                            )}`}
                          >
                            <Icons.whatsapp
                              size={
                                13
                              }
                            />
                            واتساب
                          </a>
                        ) : (
                          "—"
                        )}
                      </td>

                      {canViewMap ? (
                        <td>
                          {trader.latitude !=
                            null &&
                          trader.longitude !=
                            null ? (
                            <Link
                              className="softButton"
                              href={`/map?trader=${trader.id}`}
                            >
                              <Icons.map
                                size={
                                  13
                                }
                              />
                              خريطة
                            </Link>
                          ) : (
                            "—"
                          )}
                        </td>
                      ) : null}

                      <td>
                        <div className="rowActions">
                          <Link
                            className="softButton"
                            href={`/customers/${trader.id}`}
                          >
                            فتح
                          </Link>

                          {canUpdate ? (
                            <button
                              type="button"
                              className="softButton"
                              aria-label={`تعديل ${trader.name}`}
                              title="تعديل"
                              onClick={() =>
                                startEdit(
                                  trader
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

                          {canArchive &&
                          trader.status !==
                            "inactive" ? (
                            <button
                              type="button"
                              className="dangerButton"
                              aria-label={`أرشفة ${trader.name}`}
                              title="أرشفة"
                              disabled={
                                archivingId ===
                                trader.id
                              }
                              onClick={() =>
                                archiveTrader(
                                  trader
                                )
                              }
                            >
                              <Icons.box
                                size={
                                  13
                                }
                              />
                            </button>
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  )
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
              disabled={page <= 1}
              onClick={() =>
                navigateFilters(
                  searchQuery,
                  statusFilter,
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
                navigateFilters(
                  searchQuery,
                  statusFilter,
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
            aria-labelledby="customer-modal-title"
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  {editing
                    ? "تعديل العميل"
                    : "عميل جديد"}
                </span>

                <h2 id="customer-modal-title">
                  {editing
                    ? editing.name
                    : "إضافة عميل"}
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
                  label="اسم المحل / العميل *"
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
                  label="اسم الشخص المسؤول"
                  value={
                    form.contact_name
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        contact_name:
                          value,
                      })
                    )
                  }
                />

                <PhoneField
                  label="رقم الهاتف السوري"
                  value={
                    form.phone
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        phone:
                          value,
                      })
                    )
                  }
                />

                <PhoneField
                  label="رقم واتساب السوري"
                  value={
                    form.whatsapp
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        whatsapp:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="المنطقة"
                  value={
                    form.area
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        area: value,
                      })
                    )
                  }
                />

                <label className="field">
                  <span>
                    الحالة
                  </span>

                  <select
                    value={
                      form.status
                    }
                    onChange={(
                      event
                    ) =>
                      setForm(
                        (
                          current
                        ) => ({
                          ...current,
                          status:
                            event
                              .target
                              .value as Status,
                        })
                      )
                    }
                  >
                    {statusOptions.map(
                      ([
                        key,
                        value,
                      ]) => (
                        <option
                          key={
                            key
                          }
                          value={
                            key
                          }
                        >
                          {
                            value
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                <Field
                  label="العنوان"
                  value={
                    form.address
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
                        address:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="Latitude"
                  value={
                    form.latitude
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        latitude:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="Longitude"
                  value={
                    form.longitude
                  }
                  onChange={(
                    value
                  ) =>
                    setForm(
                      (
                        current
                      ) => ({
                        ...current,
                        longitude:
                          value,
                      })
                    )
                  }
                />

                <div className="field">
                  <span>
                    الموقع
                  </span>

                  <button
                    type="button"
                    className="softButton"
                    onClick={
                      useLocation
                    }
                  >
                    <Icons.map
                      size={14}
                    />
                    استخدم موقعي الحالي
                  </button>
                </div>

                <label className="field">
                  <span>
                    حملات واتساب
                  </span>

                  <select
                    value={
                      form.optin
                        ? "yes"
                        : "no"
                    }
                    onChange={(
                      event
                    ) =>
                      setForm(
                        (
                          current
                        ) => ({
                          ...current,
                          optin:
                            event
                              .target
                              .value ===
                            "yes",
                        })
                      )
                    }
                  >
                    <option value="no">
                      غير موافق
                    </option>

                    <option value="yes">
                      موافق على الرسائل
                    </option>
                  </select>
                </label>

                {canViewBalance ? (
                  <>
                    <label className="field">
                      <span>
                        حد الائتمان
                      </span>

                      <input
                        type="number"
                        min="0"
                        step="0.01"
                        placeholder="بدون حد"
                        value={
                          form.credit_limit
                        }
                        onChange={(
                          event
                        ) =>
                          setForm(
                            (
                              current
                            ) => ({
                              ...current,
                              credit_limit:
                                event
                                  .target
                                  .value,
                            })
                          )
                        }
                      />

                      <small className="helpText">
                        اتركه فارغاً إذا لم يوجد حد ائتمان.
                      </small>
                    </label>

                    <label className="field">
                      <span>
                        مهلة الدفع (يوم)
                      </span>

                      <input
                        type="number"
                        min="0"
                        max="3650"
                        step="1"
                        value={
                          form.payment_terms_days
                        }
                        onChange={(
                          event
                        ) =>
                          setForm(
                            (
                              current
                            ) => ({
                              ...current,
                              payment_terms_days:
                                event
                                  .target
                                  .value,
                            })
                          )
                        }
                      />

                      <small className="helpText">
                        0 يعني الدفع مستحق بنفس اليوم.
                      </small>
                    </label>
                  </>
                ) : null}

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={4}
                    value={
                      form.notes
                    }
                    onChange={(
                      event
                    ) =>
                      setForm(
                        (
                          current
                        ) => ({
                          ...current,
                          notes:
                            event
                              .target
                              .value,
                        })
                      )
                    }
                  />
                </label>
              </div>

              {formMessage ? (
                <div
                  className="toastError"
                  role="alert"
                  aria-live="polite"
                  style={{
                    marginTop: 12,
                  }}
                >
                  {
                    formMessage
                  }
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
                      : "إضافة العميل"}
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
  onChange: (
    value: string
  ) => void;
  full?: boolean;
}) {
  return (
    <label
      className={`field ${
        full ? "full" : ""
      }`}
    >
      <span>{label}</span>

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

function PhoneField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (
    value: string
  ) => void;
}) {
  const state =
    syrianPhoneState(value);

  return (
    <label className="field">
      <span>{label}</span>

      <input
        dir="ltr"
        placeholder="0944123456"
        value={value}
        onChange={(
          event
        ) =>
          onChange(
            event.target.value
          )
        }
      />

      <small
        className={
          state === "valid"
            ? "validText"
            : state ===
                "invalid"
              ? "invalidText"
              : "helpText"
        }
      >
        {state === "valid"
          ? "✓ رقم سوري صحيح"
          : state ===
              "invalid"
            ? "الرقم غير صحيح"
            : "09xxxxxxxx أو +9639xxxxxxxx"}
      </small>
    </label>
  );
}

function Mini({
  n,
  t,
}: {
  n: number | string;
  t: string;
}) {
  return (
    <div className="statCard">
      <div className="statLabel">
        {t}
      </div>

      <div className="statValue">
        {n}
      </div>
    </div>
  );
}