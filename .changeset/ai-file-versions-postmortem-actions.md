---
"better-supabase": minor
---

AI documents keep their versions in the `versions` block, and `ai-files` now requires it. Each
version is a `versions` row with `subject_type = 'ai_document'` and the text in `content`.
`better-supabase upgrade` moves the rows of `ai_document_versions` and drops that table. An edit
that leaves the text unchanged writes no version, a document keeps its latest 50 versions, and
the versions functions and RLS keep document versions private to ai-files. The
`blocks["ai-files"].tables.versions` key is removed.

With the `tasks` block installed, incident postmortem action items are tasks.
`addPostmortemAction(postmortemId, { title, assigneeId, dueAt })` creates one and links it in the
new `incident_postmortem_actions` table, `removePostmortemAction(actionId)` removes the link, and
a postmortem's `actions` lists the linked tasks. `actionItems` is deprecated and is removed in
0.48; with `tasks`, `savePostmortem` refuses it. `codemod 0.47` lists the lines that use
`actionItems` or `ai_document_versions`.
