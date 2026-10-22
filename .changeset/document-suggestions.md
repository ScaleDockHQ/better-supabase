---
"better-supabase": minor
---

Documents now take suggestions and named versions.

- `suggest(documentId, update, summary)` stores a Yjs update as a suggestion without changing the document. Members get the new `documents.suggest` permission, so someone who can only read a subject can still suggest.
- `suggestions(documentId)` lists them, and `decideSuggestion(id, decision, note)` accepts, rejects or withdraws one. Accepting appends the update to the log with the author as its actor.
- The provider from `better-supabase/yjs` takes `mode: "suggest"` and `setMode()`, keeps edits as a draft in that mode, and adds `submitSuggestion()` and `acceptSuggestion()`. `open` returns `canSuggest`.
- `nameVersion(documentId, versionId, label)` names or unnames a version, `versions(documentId, { named: true })` lists the named ones, and each version carries `source` and `frozen`.
- New events: `document.suggested`, `document.suggestion_accepted` and `document.suggestion_rejected`.

Run `better-supabase sql sync`, then generate a migration. If you list role permissions yourself, add `documents.suggest` where members should suggest.
