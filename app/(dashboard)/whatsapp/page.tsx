import { Topbar } from "@/components/topbar";
import { getCurrentContext } from "@/lib/current-context";

export default async function WhatsAppPage() {
  const { companyName } = await getCurrentContext();

  return (
    <>
      <Topbar
        title="مركز واتساب"
        subtitle="إدارة الرسائل والحملات والأتمتة"
        companyName={companyName}
      />

      <div className="page">
        <section className="heroStrip">
          <span className="eyebrow">مركز واتساب</span>
          <h2>مركز واتساب رح يكون جزء أساسي من النظام</h2>
          <p>
            هون رح نبني لاحقاً الرسائل، القوالب، الحملات، الجدولة،
            الأتمتة، سجل الإرسال والاستقبال وربط WhatsApp Cloud API.
          </p>
        </section>

        <section className="statsGrid">
          <div className="statCard">
            <div className="statLabel">حالة الربط</div>
            <div className="statValue">غير مربوط</div>
          </div>

          <div className="statCard">
            <div className="statLabel">الحملات</div>
            <div className="statValue">0</div>
          </div>

          <div className="statCard">
            <div className="statLabel">الرسائل</div>
            <div className="statValue">0</div>
          </div>

          <div className="statCard">
            <div className="statLabel">الأتمتة</div>
            <div className="statValue">0</div>
          </div>
        </section>

        <section className="panel panelPad" style={{ marginTop: 14 }}>
          <div className="empty">
            <h3>مركز واتساب قيد التطوير</h3>
            <p>
              منرجعله بعد ما نكمل أساس النظام، ومنبنيه بشكل احترافي من الصفر.
            </p>
          </div>
        </section>
      </div>
    </>
  );
}
