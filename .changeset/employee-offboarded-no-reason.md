---
"better-supabase": patch
---

`employee.offboarded` no longer carries the free-text `reason`, so outbox consumers and outbound webhooks never receive it. The reason stays on the employee (`offboard_reason`); a consumer that needs it reads the employee.
