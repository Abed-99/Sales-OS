"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { createClient } from "@/lib/supabase/client";

type Membership = {
  companyId: string;
  companyName: string;
  currency: string;
  roleId: string;
  roleName: string;
  isOwner: boolean;
  permissions: string[];
};

export function AccountMenu({
  userName,
  email,
  roleName,
  isOwner,
  companyId,
  memberships,
}: {
  userName: string;
  email: string;
  roleName: string;
  isOwner: boolean;
  companyId: string;
  memberships: Membership[];
}) {
  const router = useRouter();

  const [open, setOpen] =
    useState(false);

  const [busy, setBusy] =
    useState(false);

  const [message, setMessage] =
    useState("");

  async function switchCompany(
    nextCompanyId: string
  ) {
    if (
      nextCompanyId === companyId ||
      busy
    ) {
      return;
    }

    setBusy(true);
    setMessage("");

    try {
      const response =
        await fetch(
          "/api/company/switch",
          {
            method: "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body: JSON.stringify({
              companyId:
                nextCompanyId,
            }),
          }
        );

      if (!response.ok) {
        setMessage(
          "تعذر تبديل الشركة. حاول مرة أخرى."
        );
        return;
      }

      setOpen(false);

      router.replace("/");
      router.refresh();
    } catch {
      setMessage(
        "تعذر الاتصال بالخادم."
      );
    } finally {
      setBusy(false);
    }
  }

  async function logout() {
    if (busy) return;

    setBusy(true);
    setMessage("");

    try {
      const supabase =
        createClient();

      const { error } =
        await supabase.auth
          .signOut();

      if (error) {
        setMessage(
          "تعذر تسجيل الخروج. حاول مرة أخرى."
        );
        return;
      }

      router.replace("/login");
      router.refresh();
    } catch {
      setMessage(
        "تعذر تسجيل الخروج بسبب مشكلة في الاتصال."
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="accountMenu">
      <button
        type="button"
        className="profileMini profileButton"
        onClick={() =>
          setOpen(
            (value) => !value
          )
        }
        aria-expanded={open}
        aria-haspopup="menu"
      >
        <div className="avatar">
          {userName.charAt(0) ||
            "م"}
        </div>

        <div>
          <strong>
            {userName}
          </strong>

          <span>
            {roleName}
          </span>
        </div>

        <span className="accountChevron">
          ⌄
        </span>
      </button>

      {open ? (
        <div
          className="accountDropdown"
          role="menu"
        >
          <div className="accountIdentity">
            <strong>
              {userName}
            </strong>

            <span>
              {email}
            </span>
          </div>

          {message ? (
            <div
              className="toastError"
              role="alert"
              aria-live="polite"
            >
              {message}
            </div>
          ) : null}

          {memberships.length > 1 ? (
            <>
              <div className="accountSectionTitle">
                الشركات
              </div>

              <div className="companyChoices">
                {memberships.map(
                  (membership) => (
                    <button
                      type="button"
                      key={
                        membership.companyId
                      }
                      disabled={busy}
                      className={
                        membership.companyId ===
                        companyId
                          ? "companyChoice active"
                          : "companyChoice"
                      }
                      onClick={() =>
                        void switchCompany(
                          membership.companyId
                        )
                      }
                    >
                      <span>
                        {
                          membership.companyName
                        }
                      </span>

                      {membership.companyId ===
                      companyId ? (
                        <small>
                          الحالية
                        </small>
                      ) : null}
                    </button>
                  )
                )}
              </div>
            </>
          ) : null}

          <div className="accountDivider" />

          {isOwner ? (
            <Link
              href="/owner"
              className="accountAction"
              onClick={() =>
                setOpen(false)
              }
            >
              إدارة الفريق والصلاحيات
            </Link>
          ) : null}

          <Link
            href="/settings"
            className="accountAction"
            onClick={() =>
              setOpen(false)
            }
          >
            إعدادات الحساب والشركة
          </Link>

          <button
            type="button"
            className="accountAction logoutAction"
            disabled={busy}
            onClick={() =>
              void logout()
            }
          >
            {busy
              ? "جارٍ التنفيذ..."
              : "تسجيل الخروج"}
          </button>
        </div>
      ) : null}
    </div>
  );
}