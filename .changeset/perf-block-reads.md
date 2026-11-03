---
"better-supabase": minor
---

Ship reads for the data most pages share. `comments` (`list`, `counts`), `notifications` (`inbox`, `counts`), `saved-views` (`list`), `tags` (`list`, `forSubjects`) and `attachments` (`list`) now appear in `reads` in `blocks.generated.ts`, so a read set loads them with the page's own rows as `s.blocks.<instance>.<read>(args)`. `tags` gains the `subjects_tags` function behind `forSubjects`, and a read argument can be `text[]`.
