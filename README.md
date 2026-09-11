# Sales OS — V1 foundation

واجهة عربية RTL مبنية لتوزيع الأدوات الكهربائية: تجار، أصناف، موردين، طلبات، وتكامل WhatsApp Business Platform.

## Stack
- Next.js 16 App Router
- React 19.2
- TypeScript
- Supabase/PostgreSQL (migration included; UI connection is next)
- WhatsApp Cloud API (Meta Graph API v26 by default)

## What is already coded
- Responsive desktop/mobile shell with Arabic RTL design
- Dashboard
- Traders screen
- Products screen
- Suppliers screen
- Orders/workflow screen
- WhatsApp Center UI: campaigns, scheduling, recurrence, automations
- WhatsApp Cloud API template sending route
- WhatsApp webhook verification + signature validation scaffold
- Database migration for multi-company sales + WhatsApp opt-in/campaign tracking
- PWA manifest

## Run locally
```bash
npm install
cp .env.example .env.local
npm run dev
```
Then open http://localhost:3000

## WhatsApp setup
Fill `.env.local` with the Meta Business Platform credentials. The `send-template` endpoint expects a recorded marketing opt-in; in production that check must come directly from `traders` in Supabase rather than from request input.

### Example template send
POST `/api/whatsapp/send-template`
```json
{
  "to": "9639XXXXXXXX",
  "templateName": "new_products_ar",
  "languageCode": "ar",
  "imageUrl": "https://example.com/product.jpg",
  "bodyText": ["اسم التاجر", "اسم المنتج", "$12"],
  "hasMarketingOptIn": true
}
```

## Next engineering step
1. Wire Supabase SSR Auth and company switching.
2. Replace mock trader/product/order data with live queries.
3. Build campaign audience filters from trader data.
4. Persist incoming WhatsApp messages/status webhooks.
5. Add scheduled worker/cron for daily/weekly WhatsApp automations.
6. Add cashbox, expenses and real profit calculation.
