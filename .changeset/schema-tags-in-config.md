---
"better-supabase": minor
---

The CLI now reads `@bsb` table comments from `supabase/schemas` for every command, so `upgrade` and doctor see the same `subject`, `realtime`, `vector-search` and `json` entries as `gen`. The `subject` tag takes `id`, `id-type`, `tenant`, `scope`, `cascade`, `deleted-at`, `search`, `search-title`, `search-body`, `search-description`, `search-exclude`, `rank`, `rank-group`, `versions`, `versions-auto` and `can-<action>`, and `migrate schema-first` writes them. `migrate schema-first` also works when `supabase/` sits above the project folder. A config key still wins over a tag.

A new `server` table tag lists the columns signed-in users can't read (`server notes`), so `gen` types them as not selectable once a table lives in your schema files; `migrate schema-first` writes it for `access: "server"` columns.
