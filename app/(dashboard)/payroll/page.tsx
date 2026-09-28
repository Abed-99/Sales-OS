import { Topbar } from "@/components/topbar";
import {
  PayrollClient,
  type PayrollCashbox,
  type PayrollEmployee,
  type PayrollLoan,
  type PayrollRun,
} from "@/components/payroll/payroll-client";

import { getCurrentContext } from "@/lib/current-context";
import { hasAnyPermission, hasPermission } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function PayrollPage() {
  const context = await getCurrentContext();
  const supabase = await createClient();

  const canView = hasAnyPermission(
    context.permissions,
    [
      "payroll.view",
      "payroll.manage_employees",
      "payroll.process",
      "payroll.pay",
      "payroll.reports",
    ],
    context.isOwner,
  );

  const canManageEmployees = hasPermission(
    context.permissions,
    "payroll.manage_employees",
    context.isOwner,
  );

  const canProcess = hasPermission(context.permissions, "payroll.process", context.isOwner);

  const canPay = hasPermission(context.permissions, "payroll.pay", context.isOwner);

  if (!canView) {
    return (
      <>
        <Topbar title="الرواتب" subtitle="الموظفين والرواتب" companyName={context.companyName} />

        <div className="page">
          <section className="panel panelPad">ما عندك صلاحية لعرض الرواتب.</section>
        </div>
      </>
    );
  }

  const [employeesResult, loansResult, runsResult, cashboxesResult] = await Promise.all([
    supabase
      .from("employees")
      .select(
        "id,employee_number,full_name,phone,job_title,department,hire_date,termination_date,status,salary_currency,base_salary,fixed_allowances,overtime_hour_rate,social_security_employee_rate,social_security_employer_rate,income_tax_rate,default_cashbox_id,notes,created_at",
      )
      .eq("company_id", context.companyId)
      .order("full_name"),

    supabase
      .from("employee_loans")
      .select(
        "id,employee_id,loan_type,original_amount,balance_due,installment_amount,start_date,status,notes,created_at,employee_loan_disbursements(id,disbursement_date,cashbox_id)",
      )
      .eq("company_id", context.companyId)
      .order("created_at", { ascending: false }),

    supabase
      .from("payroll_runs")
      .select(
        `
        id,
        period_start,
        period_end,
        pay_date,
        status,
        currency,
        total_gross,
        total_deductions,
        total_net,
        total_paid,
        notes,
        posted_at,
        created_at,
        payroll_items(
          id,
          employee_id,
          base_salary,
          allowances,
          overtime_hours,
          overtime_amount,
          bonuses,
          absent_days,
          absence_deduction,
          loan_deduction,
          social_security_deduction,
          tax_deduction,
          other_deductions,
          employer_contribution,
          gross_pay,
          total_deductions,
          net_pay,
          paid_total,
          balance_due,
          notes,
          employees(
            id,
            employee_number,
            full_name,
            job_title,
            overtime_hour_rate,
            default_cashbox_id
          )
        )
      `,
      )
      .eq("company_id", context.companyId)
      .order("period_end", { ascending: false })
      .limit(36),

    supabase
      .from("cashboxes")
      .select("id,name,currency,active")
      .eq("company_id", context.companyId)
      .eq("active", true)
      .order("created_at"),
  ]);

  const results = [employeesResult, loansResult, runsResult, cashboxesResult];

  const pageError = results.some((result) => Boolean(result.error));

  return (
    <>
      <Topbar
        title="الرواتب والموظفين"
        subtitle="الرواتب، الإضافي، الخصومات، السلف والدفع"
        companyName={context.companyName}
      />

      {pageError && (
        <div className="page">
          <div className="toastError" role="alert">
            تعذر تحميل بعض بيانات الرواتب. حاول تحديث الصفحة.
          </div>
        </div>
      )}

      <PayrollClient
        companyId={context.companyId}
        baseCurrency={context.currency}
        employees={(employeesResult.data ?? []) as unknown as PayrollEmployee[]}
        loans={(loansResult.data ?? []) as unknown as PayrollLoan[]}
        runs={(runsResult.data ?? []) as unknown as PayrollRun[]}
        cashboxes={(cashboxesResult.data ?? []) as unknown as PayrollCashbox[]}
        canManageEmployees={canManageEmployees}
        canProcess={canProcess}
        canPay={canPay}
      />
    </>
  );
}
