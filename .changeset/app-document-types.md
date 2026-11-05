---
"better-supabase": minor
---

Document templates take app-defined types: `options.documentTypes` names a type, the app function that builds its variables and its variable contract. Templates, text blocks, snapshots, `render_document` and `freeze_document` accept the new type, and `validateDocumentTemplate` takes the app contracts as an optional argument. The built-in contract is unchanged.
