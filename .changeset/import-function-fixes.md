---
"better-supabase": patch
---

Fixes four functions that failed when they ran: `ensure_import_periods` computed a period end from a timestamp minus an integer, `import_ensure_ref` and `register_import_source` named columns their parameters shadow in `on conflict`, and `import_product` read and wrote a product price column the block's own table does not have when a prices table is installed. Doctor BS627 and BS628 skip migrations and the files the blocks write, which an app can't change.
