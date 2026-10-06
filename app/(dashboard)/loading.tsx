// بيبين فوراً لما ننتقل لصفحة، لحتى توصل بيانات الصفحة من السيرفر.
export default function Loading() {
  return (
    <div className="routeLoading" aria-busy="true" aria-label="جاري التحميل">
      <div className="routeLoadingBar" />
      <header className="topbar">
        <div>
          <div className="skel" style={{ width: 160, height: 22, marginBottom: 8 }} />
          <div className="skel" style={{ width: 230, height: 11 }} />
        </div>
      </header>
      <div className="page">
        <div className="statsGrid">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="statCard">
              <div className="skel" style={{ width: 34, height: 34, borderRadius: 10 }} />
              <div className="skel" style={{ width: "50%", height: 10, marginTop: 14 }} />
              <div className="skel" style={{ width: "70%", height: 22, marginTop: 8 }} />
            </div>
          ))}
        </div>
        <div className="panel panelPad" style={{ marginTop: 13 }}>
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <div key={i} className="skel" style={{ height: 34, marginBottom: 10 }} />
          ))}
        </div>
      </div>
    </div>
  );
}
