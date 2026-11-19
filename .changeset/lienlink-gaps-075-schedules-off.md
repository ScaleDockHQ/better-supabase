---
"better-supabase": minor
---

`blocks.<name>.schedules` switches a block timer off, such as `consents: { schedules: { expire: false } }`. Doctor BS508 and the wiring checklist leave it out, and `blockSchedules(blocks, { consents: { expire: false } })` takes the same map so the scheduler leaves it out too.
