export function Topbar({
  title,
  subtitle,
  companyName,
}: {
  title: string;
  subtitle?: string;
  companyName: string;
}) {
  return (
    <header className="topbar">
      <div>
        <h1>{title}</h1>
        {subtitle ? <p>{subtitle}</p> : null}
      </div>

      <div className="companyBadge">
        <span className="statusPulse" />
        <span>{companyName}</span>
      </div>
    </header>
  );
}