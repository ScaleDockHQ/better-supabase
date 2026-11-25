---
"better-supabase": minor
---

The invoices, quotes and deals blocks take `options.lineDiscountRates` for a line table whose discount column keeps basis points while `lineRates: "percent"` covers its tax rate. Before, `lineRates: "percent"` divided every discount by 100 on write, so such a table stored discounts 100 times too small. Set it and run `better-supabase upgrade`.
