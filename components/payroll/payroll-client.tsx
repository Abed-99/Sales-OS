"use client";

import {
  useMemo,
  useState,
} from "react";
import { useRouter } from "next/navigation";

import { Icons } from "@/components/icons";
import { createClient } from "@/lib/supabase/client";

type Relation<T> =
  | T
  | T[]
  | null;

function oneRelation<T>(
  value: Relation<T>
) {
  return Array.isArray(value)
    ? value[0] ?? null
    : value;
}

function num(
  value: unknown
) {
  const result =
    Number(value || 0);

  return Number.isFinite(result)
    ? result
    : 0;
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

function monthNow() {
  return today().slice(0, 7);
}

export type PayrollEmployee = {
  id: string;
  employee_number: string | null;
  full_name: string;
  phone: string | null;
  job_title: string | null;
  department: string | null;
  hire_date: string | null;
  termination_date: string | null;
  status:
    | "active"
    | "inactive"
    | "terminated";
  salary_currency: string;
  base_salary: number;
  fixed_allowances: number;
  overtime_hour_rate: number;
  social_security_employee_rate: number;
  social_security_employer_rate: number;
  income_tax_rate: number;
  default_cashbox_id: string | null;
  notes: string | null;
  created_at: string;
};

export type PayrollLoan = {
  id: string;
  employee_id: string;
  loan_type:
    | "advance"
    | "loan";
  original_amount: number;
  balance_due: number;
  installment_amount: number;
  start_date: string;
  status:
    | "active"
    | "settled"
    | "cancelled";
  notes: string | null;
  created_at: string;
};

type PayrollItemEmployee = {
  id: string;
  employee_number: string | null;
  full_name: string;
  job_title: string | null;
  overtime_hour_rate: number;
  default_cashbox_id: string | null;
};

export type PayrollItem = {
  id: string;
  employee_id: string;
  base_salary: number;
  allowances: number;
  overtime_hours: number;
  overtime_amount: number;
  bonuses: number;
  absent_days: number;
  absence_deduction: number;
  loan_deduction: number;
  social_security_deduction: number;
  tax_deduction: number;
  other_deductions: number;
  employer_contribution: number;
  gross_pay: number;
  total_deductions: number;
  net_pay: number;
  paid_total: number;
  balance_due: number;
  notes: string | null;
  employees:
    Relation<PayrollItemEmployee>;
};

export type PayrollRun = {
  id: string;
  period_start: string;
  period_end: string;
  pay_date: string | null;
  status:
    | "draft"
    | "posted"
    | "partial"
    | "paid"
    | "cancelled";
  currency: string;
  total_gross: number;
  total_deductions: number;
  total_net: number;
  total_paid: number;
  notes: string | null;
  posted_at: string | null;
  created_at: string;
  payroll_items: PayrollItem[];
};

export type PayrollCashbox = {
  id: string;
  name: string;
  currency: string;
  active: boolean;
};

type Tab =
  | "employees"
  | "payroll"
  | "loans";

type EmployeeForm = {
  employeeNumber: string;
  name: string;
  phone: string;
  jobTitle: string;
  department: string;
  hireDate: string;
  currency: string;
  baseSalary: string;
  allowances: string;
  overtimeRate: string;
  employeeSocialRate: string;
  employerSocialRate: string;
  incomeTaxRate: string;
  cashboxId: string;
  notes: string;
  status:
    | "active"
    | "inactive"
    | "terminated";
};

const emptyEmployee = (
  currency: string
): EmployeeForm => ({
  employeeNumber: "",
  name: "",
  phone: "",
  jobTitle: "",
  department: "",
  hireDate: today(),
  currency,
  baseSalary: "",
  allowances: "",
  overtimeRate: "",
  employeeSocialRate: "0",
  employerSocialRate: "0",
  incomeTaxRate: "0",
  cashboxId: "",
  notes: "",
  status: "active",
});

export function PayrollClient({
  companyId,
  baseCurrency,
  employees,
  loans,
  runs,
  cashboxes,
  canManageEmployees,
  canProcess,
  canPay,
}: {
  companyId: string;
  baseCurrency: string;
  employees: PayrollEmployee[];
  loans: PayrollLoan[];
  runs: PayrollRun[];
  cashboxes: PayrollCashbox[];
  canManageEmployees: boolean;
  canProcess: boolean;
  canPay: boolean;
}) {
  const [supabase] =
    useState(() => createClient());

  const router = useRouter();

  const [tab, setTab] =
    useState<Tab>("employees");

  const [saving, setSaving] =
    useState(false);

  const [message, setMessage] =
    useState("");

  const [
    employeeOpen,
    setEmployeeOpen,
  ] = useState(false);

  const [
    editingEmployee,
    setEditingEmployee,
  ] =
    useState<PayrollEmployee | null>(
      null
    );

  const [
    employeeForm,
    setEmployeeForm,
  ] =
    useState<EmployeeForm>(
      emptyEmployee(
        baseCurrency
      )
    );

  const [
    loanOpen,
    setLoanOpen,
  ] = useState(false);

  const [
    loanEmployee,
    setLoanEmployee,
  ] = useState("");

  const [
    loanType,
    setLoanType,
  ] = useState<
    "advance" | "loan"
  >("advance");

  const [
    loanAmount,
    setLoanAmount,
  ] = useState("");

  const [
    loanInstallment,
    setLoanInstallment,
  ] = useState("");

  const [
    loanStart,
    setLoanStart,
  ] = useState(today());

  const [
    loanNotes,
    setLoanNotes,
  ] = useState("");

  const [
    runOpen,
    setRunOpen,
  ] = useState(false);

  const [
    runMonth,
    setRunMonth,
  ] = useState(
    monthNow()
  );

  const [
    runPayDate,
    setRunPayDate,
  ] = useState(today());

  const [
    runCurrency,
    setRunCurrency,
  ] = useState(
    baseCurrency
  );

  const [
    runNotes,
    setRunNotes,
  ] = useState("");

  const [
    selectedRunId,
    setSelectedRunId,
  ] = useState(
    runs[0]?.id || ""
  );

  const [
    editItem,
    setEditItem,
  ] =
    useState<PayrollItem | null>(
      null
    );

  const [
    itemAllowances,
    setItemAllowances,
  ] = useState("");

  const [
    itemOvertimeHours,
    setItemOvertimeHours,
  ] = useState("");

  const [
    itemOvertimeAmount,
    setItemOvertimeAmount,
  ] = useState("");

  const [
    itemBonuses,
    setItemBonuses,
  ] = useState("");

  const [
    itemAbsentDays,
    setItemAbsentDays,
  ] = useState("");

  const [
    itemAbsenceDeduction,
    setItemAbsenceDeduction,
  ] = useState("");

  const [
    itemLoanDeduction,
    setItemLoanDeduction,
  ] = useState("");

  const [
    itemSocialDeduction,
    setItemSocialDeduction,
  ] = useState("");

  const [
    itemTaxDeduction,
    setItemTaxDeduction,
  ] = useState("");

  const [
    itemOtherDeductions,
    setItemOtherDeductions,
  ] = useState("");

  const [
    itemEmployerContribution,
    setItemEmployerContribution,
  ] = useState("");

  const [
    itemNotes,
    setItemNotes,
  ] = useState("");

  const [
    paymentItem,
    setPaymentItem,
  ] =
    useState<PayrollItem | null>(
      null
    );

  const [
    paymentCashbox,
    setPaymentCashbox,
  ] = useState("");

  const [
    paymentAmount,
    setPaymentAmount,
  ] = useState("");

  const [
    paymentDate,
    setPaymentDate,
  ] = useState(today());

  const [
    paymentMethod,
    setPaymentMethod,
  ] = useState("cash");

  const [
    paymentReference,
    setPaymentReference,
  ] = useState("");

  const [
    paymentNotes,
    setPaymentNotes,
  ] = useState("");

  const activeEmployees =
    employees.filter(
      (employee) =>
        employee.status ===
        "active"
    );

  const monthlyPayroll =
    activeEmployees.reduce(
      (sum, employee) =>
        sum +
        num(
          employee.base_salary
        ) +
        num(
          employee.fixed_allowances
        ),
      0
    );

  const activeLoanBalance =
    loans
      .filter(
        (loan) =>
          loan.status ===
          "active"
      )
      .reduce(
        (sum, loan) =>
          sum +
          num(
            loan.balance_due
          ),
        0
      );

  const outstandingPayroll =
    runs
      .filter(
        (run) =>
          run.status ===
            "posted" ||
          run.status ===
            "partial"
      )
      .reduce(
        (sum, run) =>
          sum +
          Math.max(
            num(
              run.total_net
            ) -
              num(
                run.total_paid
              ),
            0
          ),
        0
      );

  const selectedRun =
    useMemo(
      () =>
        runs.find(
          (run) =>
            run.id ===
            selectedRunId
        ) ??
        runs[0] ??
        null,
      [
        runs,
        selectedRunId,
      ]
    );

  function employeeName(
    employeeId: string
  ) {
    return (
      employees.find(
        (employee) =>
          employee.id ===
          employeeId
      )?.full_name ||
      "موظف"
    );
  }

  function openNewEmployee() {
    setEditingEmployee(
      null
    );

    setEmployeeForm(
      emptyEmployee(
        baseCurrency
      )
    );

    setMessage("");
    setEmployeeOpen(
      true
    );
  }

  function openEditEmployee(
    employee: PayrollEmployee
  ) {
    setEditingEmployee(
      employee
    );

    setEmployeeForm({
      employeeNumber:
        employee.employee_number ||
        "",
      name:
        employee.full_name,
      phone:
        employee.phone || "",
      jobTitle:
        employee.job_title ||
        "",
      department:
        employee.department ||
        "",
      hireDate:
        employee.hire_date ||
        today(),
      currency:
        employee.salary_currency,
      baseSalary:
        String(
          num(
            employee.base_salary
          )
        ),
      allowances:
        String(
          num(
            employee.fixed_allowances
          )
        ),
      overtimeRate:
        String(
          num(
            employee.overtime_hour_rate
          )
        ),
      employeeSocialRate:
        String(
          num(
            employee.social_security_employee_rate
          )
        ),
      employerSocialRate:
        String(
          num(
            employee.social_security_employer_rate
          )
        ),
      incomeTaxRate:
        String(
          num(
            employee.income_tax_rate
          )
        ),
      cashboxId:
        employee.default_cashbox_id ||
        "",
      notes:
        employee.notes || "",
      status:
        employee.status,
    });

    setMessage("");
    setEmployeeOpen(
      true
    );
  }

  async function saveEmployee(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !employeeForm.name.trim()
    ) {
      setMessage(
        "اسم الموظف مطلوب."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "save_employee",
        {
          target_company:
            companyId,

          target_employee:
            editingEmployee?.id ||
            null,

          target_employee_number:
            employeeForm.employeeNumber.trim() ||
            null,

          target_name:
            employeeForm.name.trim(),

          target_phone:
            employeeForm.phone.trim() ||
            null,

          target_job_title:
            employeeForm.jobTitle.trim() ||
            null,

          target_department:
            employeeForm.department.trim() ||
            null,

          target_hire_date:
            employeeForm.hireDate ||
            null,

          target_salary_currency:
            employeeForm.currency,

          target_base_salary:
            num(
              employeeForm.baseSalary
            ),

          target_fixed_allowances:
            num(
              employeeForm.allowances
            ),

          target_overtime_rate:
            num(
              employeeForm.overtimeRate
            ),

          target_employee_social_rate:
            num(
              employeeForm.employeeSocialRate
            ),

          target_employer_social_rate:
            num(
              employeeForm.employerSocialRate
            ),

          target_income_tax_rate:
            num(
              employeeForm.incomeTaxRate
            ),

          target_cashbox:
            employeeForm.cashboxId ||
            null,

          target_notes:
            employeeForm.notes.trim() ||
            null,

          target_status:
            employeeForm.status,
        }
      );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ عملية الرواتب. تحقق من البيانات والصلاحيات وحاول مرة ثانية.");
      return;
    }

    setEmployeeOpen(
      false
    );

    router.refresh();
  }

  function openLoan() {
    setLoanEmployee(
      activeEmployees[0]?.id ||
        ""
    );

    setLoanType(
      "advance"
    );

    setLoanAmount("");
    setLoanInstallment("");
    setLoanStart(today());
    setLoanNotes("");
    setMessage("");
    setLoanOpen(true);
  }

  async function saveLoan(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !loanEmployee ||
      num(
        loanAmount
      ) <= 0
    ) {
      setMessage(
        "اختار الموظف واكتب مبلغ صحيح."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "create_employee_loan",
        {
          target_company:
            companyId,

          target_employee:
            loanEmployee,

          target_type:
            loanType,

          target_amount:
            num(
              loanAmount
            ),

          target_installment:
            num(
              loanInstallment
            ),

          target_start_date:
            loanStart,

          target_notes:
            loanNotes.trim() ||
            null,
        }
      );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ عملية الرواتب. تحقق من البيانات والصلاحيات وحاول مرة ثانية.");
      return;
    }

    setLoanOpen(false);
    router.refresh();
  }

  function payrollDates() {
    const [
      year,
      month,
    ] =
      runMonth
        .split("-")
        .map(Number);

    if (!year || !month) {
      return null;
    }

    const start =
      `${year}-${String(
        month
      ).padStart(
        2,
        "0"
      )}-01`;

    const end =
      new Date(
        Date.UTC(
          year,
          month,
          0
        )
      )
        .toISOString()
        .slice(0, 10);

    return {
      start,
      end,
    };
  }

  async function createRun(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    const dates =
      payrollDates();

    if (!dates) {
      setMessage(
        "اختار شهر صحيح."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const {
      data,
      error,
    } =
      await supabase.rpc(
        "create_payroll_run",
        {
          target_company:
            companyId,

          target_period_start:
            dates.start,

          target_period_end:
            dates.end,

          target_pay_date:
            runPayDate ||
            null,

          target_currency:
            runCurrency,

          target_notes:
            runNotes.trim() ||
            null,
        }
      );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ عملية الرواتب. تحقق من البيانات والصلاحيات وحاول مرة ثانية.");
      return;
    }

    if (
      typeof data ===
      "string"
    ) {
      setSelectedRunId(
        data
      );
    }

    setRunOpen(false);
    router.refresh();
  }

  async function postRun(
    runId: string
  ) {
    if (
      !window.confirm(
        "ترحيل مسير الرواتب؟ بعد الترحيل ما بيعود قابل للتعديل."
      )
    ) {
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "post_payroll_run",
        {
          target_company:
            companyId,
          target_run:
            runId,
        }
      );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ عملية الرواتب. تحقق من البيانات والصلاحيات وحاول مرة ثانية.");
      return;
    }

    router.refresh();
  }

  function openPayrollItem(
    item: PayrollItem
  ) {
    setEditItem(item);

    setItemAllowances(
      String(
        num(
          item.allowances
        )
      )
    );

    setItemOvertimeHours(
      String(
        num(
          item.overtime_hours
        )
      )
    );

    setItemOvertimeAmount(
      String(
        num(
          item.overtime_amount
        )
      )
    );

    setItemBonuses(
      String(
        num(
          item.bonuses
        )
      )
    );

    setItemAbsentDays(
      String(
        num(
          item.absent_days
        )
      )
    );

    setItemAbsenceDeduction(
      String(
        num(
          item.absence_deduction
        )
      )
    );

    setItemLoanDeduction(
      String(
        num(
          item.loan_deduction
        )
      )
    );

    setItemSocialDeduction(
      String(
        num(
          item.social_security_deduction
        )
      )
    );

    setItemTaxDeduction(
      String(
        num(
          item.tax_deduction
        )
      )
    );

    setItemOtherDeductions(
      String(
        num(
          item.other_deductions
        )
      )
    );

    setItemEmployerContribution(
      String(
        num(
          item.employer_contribution
        )
      )
    );

    setItemNotes(
      item.notes || ""
    );

    setMessage("");
  }

  function autoOvertimeAmount(
    hours: string
  ) {
    const employee =
      oneRelation(
        editItem?.employees ||
          null
      );

    const amount =
      num(hours) *
      num(
        employee?.overtime_hour_rate
      );

    setItemOvertimeHours(
      hours
    );

    setItemOvertimeAmount(
      amount > 0
        ? amount.toFixed(2)
        : "0"
    );
  }

  async function savePayrollItem(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (!editItem) {
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "update_payroll_item",
        {
          target_company:
            companyId,

          target_item:
            editItem.id,

          target_allowances:
            num(
              itemAllowances
            ),

          target_overtime_hours:
            num(
              itemOvertimeHours
            ),

          target_overtime_amount:
            num(
              itemOvertimeAmount
            ),

          target_bonuses:
            num(
              itemBonuses
            ),

          target_absent_days:
            num(
              itemAbsentDays
            ),

          target_absence_deduction:
            num(
              itemAbsenceDeduction
            ),

          target_loan_deduction:
            num(
              itemLoanDeduction
            ),

          target_social_security_deduction:
            num(
              itemSocialDeduction
            ),

          target_tax_deduction:
            num(
              itemTaxDeduction
            ),

          target_other_deductions:
            num(
              itemOtherDeductions
            ),

          target_employer_contribution:
            num(
              itemEmployerContribution
            ),

          target_notes:
            itemNotes.trim() ||
            null,
        }
      );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ عملية الرواتب. تحقق من البيانات والصلاحيات وحاول مرة ثانية.");
      return;
    }

    setEditItem(null);
    router.refresh();
  }

  function openPayment(
    item: PayrollItem,
    run: PayrollRun
  ) {
    const employee =
      oneRelation(
        item.employees
      );

    const matching =
      cashboxes.find(
        (cashbox) =>
          cashbox.id ===
            employee?.default_cashbox_id &&
          cashbox.currency ===
            run.currency
      ) ??
      cashboxes.find(
        (cashbox) =>
          cashbox.currency ===
          run.currency
      );

    setPaymentItem(item);

    setPaymentCashbox(
      matching?.id || ""
    );

    setPaymentAmount(
      String(
        num(
          item.balance_due
        )
      )
    );

    setPaymentDate(
      today()
    );

    setPaymentMethod(
      "cash"
    );

    setPaymentReference("");
    setPaymentNotes("");
    setMessage("");
  }

  async function savePayment(
    event:
      React.FormEvent<HTMLFormElement>
  ) {
    event.preventDefault();

    if (
      !paymentItem ||
      !paymentCashbox ||
      num(
        paymentAmount
      ) <= 0
    ) {
      setMessage(
        "اختار الصندوق واكتب مبلغ صحيح."
      );
      return;
    }

    setSaving(true);
    setMessage("");

    const { error } =
      await supabase.rpc(
        "record_payroll_payment",
        {
          target_company:
            companyId,

          target_payroll_item:
            paymentItem.id,

          target_cashbox:
            paymentCashbox,

          target_amount:
            num(
              paymentAmount
            ),

          target_payment_date:
            paymentDate,

          target_method:
            paymentMethod,

          target_reference:
            paymentReference.trim() ||
            null,

          target_notes:
            paymentNotes.trim() ||
            null,
        }
      );

    setSaving(false);

    if (error) {
      setMessage("تعذر تنفيذ عملية الرواتب. تحقق من البيانات والصلاحيات وحاول مرة ثانية.");
      return;
    }

    setPaymentItem(null);
    router.refresh();
  }

  const tabButton = (
    key: Tab,
    label: string
  ) => (
    <button
      type="button"
      className={
        tab === key
          ? "primaryButton"
          : "softButton"
      }
      onClick={() =>
        setTab(key)
      }
    >
      {label}
    </button>
  );

  return (
    <div className="page">
      <div className="pageTitle">
        <div>
          <span className="eyebrow">
            Payroll & HR
          </span>

          <h2>
            الرواتب والموظفين
          </h2>

          <p className="muted">
            إدارة الرواتب الشهرية والسلف والخصومات والدفع من مكان واحد.
          </p>
        </div>

        <div className="rowActions">
          {canManageEmployees && (
            <button
              type="button"
              className="softButton"
              onClick={
                openLoan
              }
            >
              <Icons.money
                size={14}
              />
              سلفة / قرض
            </button>
          )}

          {canProcess && (
            <button
              type="button"
              className="softButton"
              onClick={() => {
                setMessage("");
                setRunOpen(
                  true
                );
              }}
            >
              <Icons.plus
                size={14}
              />
              مسير رواتب
            </button>
          )}

          {canManageEmployees && (
            <button
              type="button"
              className="primaryButton"
              onClick={
                openNewEmployee
              }
            >
              <Icons.plus
                size={14}
              />
              موظف جديد
            </button>
          )}
        </div>
      </div>

      <section className="statsGrid">
        <Mini
          title="الموظفين النشطين"
          value={String(
            activeEmployees.length
          )}
        />

        <Mini
          title="الرواتب الثابتة الشهرية"
          value={`${monthlyPayroll.toFixed(
            2
          )} ${baseCurrency}`}
        />

        <Mini
          title="سلف وقروض قائمة"
          value={`${activeLoanBalance.toFixed(
            2
          )}`}
        />

        <Mini
          title="رواتب مستحقة"
          value={`${outstandingPayroll.toFixed(
            2
          )}`}
        />
      </section>

      <div
        className="rowActions"
        style={{
          marginTop: 14,
          flexWrap: "wrap",
        }}
      >
        {tabButton(
          "employees",
          "الموظفين"
        )}

        {tabButton(
          "payroll",
          "مسيرات الرواتب"
        )}

        {tabButton(
          "loans",
          "السلف والقروض"
        )}
      </div>

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

      {tab ===
        "employees" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          {!employees.length ? (
            <div className="empty">
              <Icons.users
                size={30}
              />

              <h3>
                ما في موظفين
              </h3>

              <p>
                أضف أول موظف حتى نبدأ نظام الرواتب.
              </p>
            </div>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الموظف</th>
                    <th>الوظيفة</th>
                    <th>القسم</th>
                    <th>الراتب</th>
                    <th>البدلات</th>
                    <th>العملة</th>
                    <th>الحالة</th>
                    <th />
                  </tr>
                </thead>

                <tbody>
                  {employees.map(
                    (employee) => (
                      <tr
                        key={
                          employee.id
                        }
                      >
                        <td>
                          <strong>
                            {
                              employee.full_name
                            }
                          </strong>

                          <div className="muted">
                            {employee.employee_number ||
                              employee.phone ||
                              "بدون رقم"}
                          </div>
                        </td>

                        <td>
                          {employee.job_title ||
                            "—"}
                        </td>

                        <td>
                          {employee.department ||
                            "—"}
                        </td>

                        <td>
                          {num(
                            employee.base_salary
                          ).toFixed(
                            2
                          )}
                        </td>

                        <td>
                          {num(
                            employee.fixed_allowances
                          ).toFixed(
                            2
                          )}
                        </td>

                        <td>
                          {
                            employee.salary_currency
                          }
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              employee.status ===
                              "active"
                                ? "green"
                                : "gray"
                            }`}
                          >
                            {employee.status ===
                            "active"
                              ? "نشط"
                              : employee.status ===
                                "terminated"
                              ? "منتهي"
                              : "موقوف"}
                          </span>
                        </td>

                        <td>
                          {canManageEmployees && (
                            <button
                              type="button"
                              className="softButton"
                              onClick={() =>
                                openEditEmployee(
                                  employee
                                )
                              }
                            >
                              <Icons.edit
                                size={13}
                              />
                              تعديل
                            </button>
                          )}
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      {tab ===
        "loans" && (
        <section
          className="panel"
          style={{
            marginTop: 14,
          }}
        >
          {!loans.length ? (
            <div className="empty">
              <Icons.money
                size={28}
              />

              <h3>
                ما في سلف أو قروض
              </h3>
            </div>
          ) : (
            <div className="tableWrap">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>الموظف</th>
                    <th>النوع</th>
                    <th>الأصل</th>
                    <th>المتبقي</th>
                    <th>قسط الرواتب</th>
                    <th>البداية</th>
                    <th>الحالة</th>
                  </tr>
                </thead>

                <tbody>
                  {loans.map(
                    (loan) => (
                      <tr
                        key={
                          loan.id
                        }
                      >
                        <td>
                          <strong>
                            {employeeName(
                              loan.employee_id
                            )}
                          </strong>
                        </td>

                        <td>
                          {loan.loan_type ===
                          "advance"
                            ? "سلفة"
                            : "قرض"}
                        </td>

                        <td>
                          {num(
                            loan.original_amount
                          ).toFixed(
                            2
                          )}
                        </td>

                        <td>
                          {num(
                            loan.balance_due
                          ).toFixed(
                            2
                          )}
                        </td>

                        <td>
                          {num(
                            loan.installment_amount
                          ).toFixed(
                            2
                          )}
                        </td>

                        <td>
                          {
                            loan.start_date
                          }
                        </td>

                        <td>
                          <span
                            className={`chip ${
                              loan.status ===
                              "active"
                                ? "orange"
                                : loan.status ===
                                  "settled"
                                ? "green"
                                : "gray"
                            }`}
                          >
                            {loan.status ===
                            "active"
                              ? "قائم"
                              : loan.status ===
                                "settled"
                              ? "مسدد"
                              : "ملغى"}
                          </span>
                        </td>
                      </tr>
                    )
                  )}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      {tab ===
        "payroll" && (
        <div
          className="pageGrid"
          style={{
            marginTop: 14,
          }}
        >
          <aside className="panel panelPad">
            <div className="panelHeader">
              <div>
                <h2>
                  المسيرات
                </h2>

                <p>
                  آخر الرواتب الشهرية
                </p>
              </div>
            </div>

            {!runs.length ? (
              <p className="muted">
                ما في مسيرات رواتب.
              </p>
            ) : (
              <div className="quickList">
                {runs.map(
                  (run) => (
                    <button
                      type="button"
                      key={
                        run.id
                      }
                      className="quickItem"
                      style={{
                        width:
                          "100%",
                        textAlign:
                          "right",
                        cursor:
                          "pointer",
                      }}
                      onClick={() =>
                        setSelectedRunId(
                          run.id
                        )
                      }
                    >
                      <div>
                        <strong>
                          {run.period_start.slice(
                            0,
                            7
                          )}
                        </strong>

                        <span>
                          {run.currency} •{" "}
                          {runStatusLabel(
                            run.status
                          )}
                        </span>
                      </div>

                      <div className="count">
                        {num(
                          run.total_net
                        ).toFixed(
                          2
                        )}
                      </div>
                    </button>
                  )
                )}
              </div>
            )}
          </aside>

          <section className="panel panelPad">
            {!selectedRun ? (
              <div className="empty">
                <Icons.wallet
                  size={28}
                />

                <h3>
                  اختار مسير رواتب
                </h3>
              </div>
            ) : (
              <>
                <div className="panelHeader">
                  <div>
                    <h2>
                      رواتب{" "}
                      {selectedRun.period_start.slice(
                        0,
                        7
                      )}
                    </h2>

                    <p>
                      من{" "}
                      {
                        selectedRun.period_start
                      }{" "}
                      إلى{" "}
                      {
                        selectedRun.period_end
                      }
                    </p>
                  </div>

                  <div className="rowActions">
                    <span
                      className={`chip ${
                        selectedRun.status ===
                        "draft"
                          ? "gray"
                          : selectedRun.status ===
                            "paid"
                          ? "green"
                          : "orange"
                      }`}
                    >
                      {runStatusLabel(
                        selectedRun.status
                      )}
                    </span>

                    {canProcess &&
                      selectedRun.status ===
                        "draft" && (
                        <button
                          type="button"
                          className="primaryButton"
                          disabled={
                            saving
                          }
                          onClick={() =>
                            void postRun(
                              selectedRun.id
                            )
                          }
                        >
                          ترحيل الرواتب
                        </button>
                      )}
                  </div>
                </div>

                <section className="statsGrid">
                  <Mini
                    title="الإجمالي"
                    value={`${num(
                      selectedRun.total_gross
                    ).toFixed(
                      2
                    )} ${
                      selectedRun.currency
                    }`}
                  />

                  <Mini
                    title="الخصومات"
                    value={`${num(
                      selectedRun.total_deductions
                    ).toFixed(
                      2
                    )} ${
                      selectedRun.currency
                    }`}
                  />

                  <Mini
                    title="الصافي"
                    value={`${num(
                      selectedRun.total_net
                    ).toFixed(
                      2
                    )} ${
                      selectedRun.currency
                    }`}
                  />

                  <Mini
                    title="المدفوع"
                    value={`${num(
                      selectedRun.total_paid
                    ).toFixed(
                      2
                    )} ${
                      selectedRun.currency
                    }`}
                  />
                </section>

                <div
                  className="tableWrap"
                  style={{
                    marginTop: 15,
                  }}
                >
                  <table className="dataTable">
                    <thead>
                      <tr>
                        <th>الموظف</th>
                        <th>أساسي</th>
                        <th>إضافات</th>
                        <th>خصومات</th>
                        <th>الصافي</th>
                        <th>المدفوع</th>
                        <th>المتبقي</th>
                        <th />
                      </tr>
                    </thead>

                    <tbody>
                      {selectedRun.payroll_items.map(
                        (item) => {
                          const employee =
                            oneRelation(
                              item.employees
                            );

                          const additions =
                            num(
                              item.allowances
                            ) +
                            num(
                              item.overtime_amount
                            ) +
                            num(
                              item.bonuses
                            );

                          return (
                            <tr
                              key={
                                item.id
                              }
                            >
                              <td>
                                <strong>
                                  {employee?.full_name ||
                                    "موظف"}
                                </strong>

                                <div className="muted">
                                  {employee?.job_title ||
                                    employee?.employee_number ||
                                    ""}
                                </div>
                              </td>

                              <td>
                                {num(
                                  item.base_salary
                                ).toFixed(
                                  2
                                )}
                              </td>

                              <td>
                                {additions.toFixed(
                                  2
                                )}
                              </td>

                              <td>
                                {num(
                                  item.total_deductions
                                ).toFixed(
                                  2
                                )}
                              </td>

                              <td>
                                <strong>
                                  {num(
                                    item.net_pay
                                  ).toFixed(
                                    2
                                  )}
                                </strong>
                              </td>

                              <td>
                                {num(
                                  item.paid_total
                                ).toFixed(
                                  2
                                )}
                              </td>

                              <td>
                                {num(
                                  item.balance_due
                                ).toFixed(
                                  2
                                )}
                              </td>

                              <td>
                                <div className="rowActions">
                                  {canProcess &&
                                    selectedRun.status ===
                                      "draft" && (
                                      <button
                                        type="button"
                                        className="softButton"
                                        onClick={() =>
                                          openPayrollItem(
                                            item
                                          )
                                        }
                                      >
                                        تعديل
                                      </button>
                                    )}

                                  {canPay &&
                                    (
                                      selectedRun.status ===
                                        "posted" ||
                                      selectedRun.status ===
                                        "partial"
                                    ) &&
                                    num(
                                      item.balance_due
                                    ) > 0 && (
                                      <button
                                        type="button"
                                        className="primaryButton"
                                        onClick={() =>
                                          openPayment(
                                            item,
                                            selectedRun
                                          )
                                        }
                                      >
                                        دفع
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
              </>
            )}
          </section>
        </div>
      )}

      {employeeOpen && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 900,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Employee
                </span>

                <h2>
                  {editingEmployee
                    ? "تعديل الموظف"
                    : "موظف جديد"}
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setEmployeeOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveEmployee
              }
            >
              <div className="formGrid">
                <Field
                  label="اسم الموظف *"
                  value={
                    employeeForm.name
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        name: value,
                      })
                    )
                  }
                />

                <Field
                  label="رقم الموظف"
                  value={
                    employeeForm.employeeNumber
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        employeeNumber:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="الهاتف"
                  value={
                    employeeForm.phone
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        phone: value,
                      })
                    )
                  }
                />

                <Field
                  label="المسمى الوظيفي"
                  value={
                    employeeForm.jobTitle
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        jobTitle:
                          value,
                      })
                    )
                  }
                />

                <Field
                  label="القسم"
                  value={
                    employeeForm.department
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        department:
                          value,
                      })
                    )
                  }
                />

                <label className="field">
                  <span>
                    تاريخ التعيين
                  </span>

                  <input
                    type="date"
                    value={
                      employeeForm.hireDate
                    }
                    onChange={(
                      event
                    ) =>
                      setEmployeeForm(
                        (
                          form
                        ) => ({
                          ...form,
                          hireDate:
                            event.target
                              .value,
                        })
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    عملة الراتب
                  </span>

                  <input
                    value={
                      employeeForm.currency
                    }
                    onChange={(
                      event
                    ) =>
                      setEmployeeForm(
                        (
                          form
                        ) => ({
                          ...form,
                          currency:
                            event.target.value.toUpperCase(),
                        })
                      )
                    }
                  />
                </label>

                <MoneyField
                  label="الراتب الأساسي"
                  value={
                    employeeForm.baseSalary
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        baseSalary:
                          value,
                      })
                    )
                  }
                />

                <MoneyField
                  label="بدلات ثابتة"
                  value={
                    employeeForm.allowances
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        allowances:
                          value,
                      })
                    )
                  }
                />

                <MoneyField
                  label="سعر ساعة الإضافي"
                  value={
                    employeeForm.overtimeRate
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        overtimeRate:
                          value,
                      })
                    )
                  }
                />

                <MoneyField
                  label="ضمان الموظف %"
                  value={
                    employeeForm.employeeSocialRate
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        employeeSocialRate:
                          value,
                      })
                    )
                  }
                />

                <MoneyField
                  label="مساهمة الشركة %"
                  value={
                    employeeForm.employerSocialRate
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        employerSocialRate:
                          value,
                      })
                    )
                  }
                />

                <MoneyField
                  label="ضريبة راتب %"
                  value={
                    employeeForm.incomeTaxRate
                  }
                  setValue={(
                    value
                  ) =>
                    setEmployeeForm(
                      (form) => ({
                        ...form,
                        incomeTaxRate:
                          value,
                      })
                    )
                  }
                />

                <label className="field">
                  <span>
                    صندوق دفع الراتب
                  </span>

                  <select
                    value={
                      employeeForm.cashboxId
                    }
                    onChange={(
                      event
                    ) =>
                      setEmployeeForm(
                        (
                          form
                        ) => ({
                          ...form,
                          cashboxId:
                            event.target
                              .value,
                        })
                      )
                    }
                  >
                    <option value="">
                      بدون تحديد
                    </option>

                    {cashboxes.map(
                      (cashbox) => (
                        <option
                          key={
                            cashbox.id
                          }
                          value={
                            cashbox.id
                          }
                        >
                          {cashbox.name} -{" "}
                          {cashbox.currency}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    الحالة
                  </span>

                  <select
                    value={
                      employeeForm.status
                    }
                    onChange={(
                      event
                    ) =>
                      setEmployeeForm(
                        (
                          form
                        ) => ({
                          ...form,
                          status:
                            event.target.value as EmployeeForm["status"],
                        })
                      )
                    }
                  >
                    <option value="active">
                      نشط
                    </option>

                    <option value="inactive">
                      موقوف
                    </option>

                    <option value="terminated">
                      منتهي العمل
                    </option>
                  </select>
                </label>

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={3}
                    value={
                      employeeForm.notes
                    }
                    onChange={(
                      event
                    ) =>
                      setEmployeeForm(
                        (
                          form
                        ) => ({
                          ...form,
                          notes:
                            event.target
                              .value,
                        })
                      )
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
                  onClick={() =>
                    setEmployeeOpen(
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
                  حفظ الموظف
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {loanOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Employee Loan
                </span>

                <h2>
                  سلفة أو قرض
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setLoanOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                saveLoan
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    الموظف
                  </span>

                  <select
                    value={
                      loanEmployee
                    }
                    onChange={(
                      event
                    ) =>
                      setLoanEmployee(
                        event.target
                          .value
                      )
                    }
                  >
                    {activeEmployees.map(
                      (employee) => (
                        <option
                          key={
                            employee.id
                          }
                          value={
                            employee.id
                          }
                        >
                          {
                            employee.full_name
                          }
                        </option>
                      )
                    )}
                  </select>
                </label>

                <label className="field">
                  <span>
                    النوع
                  </span>

                  <select
                    value={
                      loanType
                    }
                    onChange={(
                      event
                    ) =>
                      setLoanType(
                        event.target.value as
                          | "advance"
                          | "loan"
                      )
                    }
                  >
                    <option value="advance">
                      سلفة
                    </option>

                    <option value="loan">
                      قرض
                    </option>
                  </select>
                </label>

                <MoneyField
                  label="المبلغ"
                  value={
                    loanAmount
                  }
                  setValue={
                    setLoanAmount
                  }
                />

                <MoneyField
                  label="الحسم الشهري المقترح"
                  value={
                    loanInstallment
                  }
                  setValue={
                    setLoanInstallment
                  }
                />

                <label className="field">
                  <span>
                    تاريخ البداية
                  </span>

                  <input
                    type="date"
                    value={
                      loanStart
                    }
                    onChange={(
                      event
                    ) =>
                      setLoanStart(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={3}
                    value={
                      loanNotes
                    }
                    onChange={(
                      event
                    ) =>
                      setLoanNotes(
                        event.target
                          .value
                      )
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
                  onClick={() =>
                    setLoanOpen(
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
                  تسجيل
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {runOpen && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Payroll Run
                </span>

                <h2>
                  إنشاء مسير رواتب
                </h2>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setRunOpen(
                    false
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                createRun
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    الشهر
                  </span>

                  <input
                    type="month"
                    value={
                      runMonth
                    }
                    onChange={(
                      event
                    ) =>
                      setRunMonth(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    عملة المسير
                  </span>

                  <input
                    value={
                      runCurrency
                    }
                    onChange={(
                      event
                    ) =>
                      setRunCurrency(
                        event.target.value.toUpperCase()
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    تاريخ الدفع المتوقع
                  </span>

                  <input
                    type="date"
                    value={
                      runPayDate
                    }
                    onChange={(
                      event
                    ) =>
                      setRunPayDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={3}
                    value={
                      runNotes
                    }
                    onChange={(
                      event
                    ) =>
                      setRunNotes(
                        event.target
                          .value
                      )
                    }
                  />
                </label>
              </div>

              <div className="modalActions">
                <button
                  type="button"
                  className="softButton"
                  onClick={() =>
                    setRunOpen(
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
                  إنشاء المسير
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {editItem && (
        <div className="modalOverlay">
          <section
            className="modal"
            style={{
              maxWidth: 900,
            }}
          >
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Payroll Details
                </span>

                <h2>
                  تعديل تفاصيل الراتب
                </h2>

                <p className="muted">
                  {oneRelation(
                    editItem.employees
                  )?.full_name ||
                    "موظف"}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setEditItem(
                    null
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                savePayrollItem
              }
            >
              <div className="formGrid">
                <MoneyField
                  label="البدلات"
                  value={
                    itemAllowances
                  }
                  setValue={
                    setItemAllowances
                  }
                />

                <MoneyField
                  label="ساعات إضافي"
                  value={
                    itemOvertimeHours
                  }
                  setValue={
                    autoOvertimeAmount
                  }
                />

                <MoneyField
                  label="قيمة الإضافي"
                  value={
                    itemOvertimeAmount
                  }
                  setValue={
                    setItemOvertimeAmount
                  }
                />

                <MoneyField
                  label="مكافآت / بونص"
                  value={
                    itemBonuses
                  }
                  setValue={
                    setItemBonuses
                  }
                />

                <MoneyField
                  label="أيام غياب"
                  value={
                    itemAbsentDays
                  }
                  setValue={
                    setItemAbsentDays
                  }
                />

                <MoneyField
                  label="خصم الغياب"
                  value={
                    itemAbsenceDeduction
                  }
                  setValue={
                    setItemAbsenceDeduction
                  }
                />

                <MoneyField
                  label="حسم سلفة / قرض"
                  value={
                    itemLoanDeduction
                  }
                  setValue={
                    setItemLoanDeduction
                  }
                />

                <MoneyField
                  label="اقتطاع الضمان"
                  value={
                    itemSocialDeduction
                  }
                  setValue={
                    setItemSocialDeduction
                  }
                />

                <MoneyField
                  label="ضريبة الراتب"
                  value={
                    itemTaxDeduction
                  }
                  setValue={
                    setItemTaxDeduction
                  }
                />

                <MoneyField
                  label="خصومات أخرى"
                  value={
                    itemOtherDeductions
                  }
                  setValue={
                    setItemOtherDeductions
                  }
                />

                <MoneyField
                  label="مساهمة الشركة"
                  value={
                    itemEmployerContribution
                  }
                  setValue={
                    setItemEmployerContribution
                  }
                />

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={3}
                    value={
                      itemNotes
                    }
                    onChange={(
                      event
                    ) =>
                      setItemNotes(
                        event.target
                          .value
                      )
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
                  onClick={() =>
                    setEditItem(
                      null
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
                  حفظ تفاصيل الراتب
                </button>
              </div>
            </form>
          </section>
        </div>
      )}

      {paymentItem && (
        <div className="modalOverlay">
          <section className="modal">
            <div className="modalHeader">
              <div>
                <span className="eyebrow">
                  Salary Payment
                </span>

                <h2>
                  دفع راتب
                </h2>

                <p className="muted">
                  {oneRelation(
                    paymentItem.employees
                  )?.full_name ||
                    "موظف"}
                </p>
              </div>

              <button
                type="button"
                className="closeButton"
                onClick={() =>
                  setPaymentItem(
                    null
                  )
                }
              >
                ×
              </button>
            </div>

            <form
              onSubmit={
                savePayment
              }
            >
              <div className="formGrid">
                <label className="field">
                  <span>
                    الصندوق
                  </span>

                  <select
                    value={
                      paymentCashbox
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentCashbox(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="">
                      اختار
                    </option>

                    {cashboxes.map(
                      (cashbox) => (
                        <option
                          key={
                            cashbox.id
                          }
                          value={
                            cashbox.id
                          }
                        >
                          {cashbox.name} -{" "}
                          {cashbox.currency}
                        </option>
                      )
                    )}
                  </select>
                </label>

                <MoneyField
                  label="المبلغ"
                  value={
                    paymentAmount
                  }
                  setValue={
                    setPaymentAmount
                  }
                />

                <label className="field">
                  <span>
                    تاريخ الدفع
                  </span>

                  <input
                    type="date"
                    value={
                      paymentDate
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentDate(
                        event.target
                          .value
                      )
                    }
                  />
                </label>

                <label className="field">
                  <span>
                    طريقة الدفع
                  </span>

                  <select
                    value={
                      paymentMethod
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentMethod(
                        event.target
                          .value
                      )
                    }
                  >
                    <option value="cash">
                      نقدي
                    </option>

                    <option value="bank">
                      بنك
                    </option>

                    <option value="card">
                      بطاقة
                    </option>

                    <option value="check">
                      شيك
                    </option>

                    <option value="other">
                      أخرى
                    </option>
                  </select>
                </label>

                <Field
                  label="رقم مرجع"
                  value={
                    paymentReference
                  }
                  setValue={
                    setPaymentReference
                  }
                />

                <label className="field full">
                  <span>
                    ملاحظات
                  </span>

                  <textarea
                    rows={3}
                    value={
                      paymentNotes
                    }
                    onChange={(
                      event
                    ) =>
                      setPaymentNotes(
                        event.target
                          .value
                      )
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
                  onClick={() =>
                    setPaymentItem(
                      null
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
                  تسجيل دفع الراتب
                </button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}

function runStatusLabel(
  status: PayrollRun["status"]
) {
  if (status === "draft") {
    return "مسودة";
  }

  if (status === "posted") {
    return "مرحّل";
  }

  if (status === "partial") {
    return "مدفوع جزئي";
  }

  if (status === "paid") {
    return "مدفوع";
  }

  return "ملغى";
}

function Field({
  label,
  value,
  setValue,
}: {
  label: string;
  value: string;
  setValue:
    (value: string) => void;
}) {
  return (
    <label className="field">
      <span>
        {label}
      </span>

      <input
        value={value}
        onChange={(
          event
        ) =>
          setValue(
            event.target.value
          )
        }
      />
    </label>
  );
}

function MoneyField({
  label,
  value,
  setValue,
}: {
  label: string;
  value: string;
  setValue:
    (value: string) => void;
}) {
  return (
    <label className="field">
      <span>
        {label}
      </span>

      <input
        type="number"
        min="0"
        step="0.01"
        value={value}
        onChange={(
          event
        ) =>
          setValue(
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