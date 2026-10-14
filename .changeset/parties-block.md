---
"better-supabase": minor
---

The `parties` SQL module and `better-supabase/blocks/parties` keep the companies and people an organization works with: lifecycle stages, owners, who works where with a role and one primary contact, dedupe by domain and email, `mergeCompanies` and `mergePeople`, and keyset-paged `listCompanies` and `listPeople`. `partiesSubjects()` registers both tables in `config.subjects` so comments, tags, files and pipelines attach to them, and the owner watches the record when notifications is installed.
