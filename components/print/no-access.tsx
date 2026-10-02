import Link from "next/link";

/** بدل ورقة فاضية وغلط: إذا المستخدم ما عندو صلاحية يشوف هالكشف. */
export function PrintNoAccess({
  backHref,
  message,
}: {
  backHref: string;
  message: string;
}) {
  return (
    <div className="printPage">
      <div className="printToolbar">
        <Link className="softButton" href={backHref}>
          رجوع
        </Link>
      </div>
      <div className="printPaper" style={{ minHeight: 0 }}>
        <p className="printNote" style={{ fontSize: 14 }}>
          {message}
        </p>
      </div>
    </div>
  );
}
