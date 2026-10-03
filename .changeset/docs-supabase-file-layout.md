---
"better-supabase": patch
---

The docs and skills follow the Naming page's file layout everywhere. The PermDock page defines `betterSupabase` in `src/lib/supabase/index.ts` and creates `bs` in `server.ts` and `client.ts`, and every Next.js `server.ts` starts with `import "server-only"`. The docs drift check now fails a code block that breaks the layout.
