---
"better-supabase": minor
---

A `party_discount_group` import puts one party in a customer discount group, or removes it when the group is empty. Quote and invoice lines still pass that party id as text when `discountMatrix` is on.
