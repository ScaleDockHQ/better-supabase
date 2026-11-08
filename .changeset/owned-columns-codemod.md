---
"better-supabase": minor
---

`better-supabase codemod owned-columns` declares, in your schema files, the columns blocks add to tables you create, as `<table>.block-columns.sql`. Doctor BS622 warns for each such column. A later release stops adding columns to tables you own and turns the feature off instead, so run the codemod before you update.
