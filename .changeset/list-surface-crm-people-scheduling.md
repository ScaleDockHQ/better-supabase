---
"better-supabase": minor
---

Five more blocks page, facet and count through the shared list implementation (ADR 0749, 0779): `sequences` (`sequencePage`, `sequenceFacets`, `sequenceCount`), `payroll-export` (`runPage`, `runFacets`, `runCount`), `passes` (`passPage`, `passFacets`, `passCount`), `enrollments` (`enrollmentPage`, `enrollmentFacets`, `enrollmentCount`) and `e-prescribing` (`prescriptionPage`, `prescriptionFacets`, `prescriptionCount`). Each takes `q`, `sort`, list filters, `after` and `limit`, declares its `sorts`, `facets` and `filters` in the manifest, and returns an `invalid_input` error for a name it does not declare. The existing `list` methods and SQL list functions keep their signatures; `sequences`, `payroll-export`, `passes` and `enrollments` gain the SQL functions `page_sequences`, `page_payroll_runs`, `page_passes` and `page_enrollments`, and `list_prescriptions` now accepts list filters, `sort`, `facet`, `count`, `after` and `paged`. `enrollments` also gains `get(enrollmentId)` over the new SQL function `get_enrollment`. Apply the generated migration to adopt the new functions.

| Before                                                                          | After                                                                                   |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `list({ status })` was the only read of sequences, runs, passes and enrollments | `sequencePage`, `runPage`, `passPage` and `enrollmentPage` with `sort` and list filters |
| No facet counts or exact counts on these blocks                                 | `<x>Facets(options)` and `<x>Count(options)` returning `{ value, exact }`               |
| An enrollment was read from the list or by program and subject                  | `enrollments.get(enrollmentId)`                                                         |
