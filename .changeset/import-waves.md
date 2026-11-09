---
"better-supabase": minor
---

Import targets can name `dependsOn`. `importWaves` orders them into waves and rejects a cycle. A batch whose earlier wave still has open chunks is refused unless the plan sets `unordered`.
