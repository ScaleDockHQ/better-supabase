---
"better-supabase": minor
---

New combined reads: `hiring.board`, `bookings.page`, `qualifications.matrix`, `documents.page` and `care.dossier`. Each runs the reads a page needs together over the existing SQL functions, so no upgrade or migration is needed.
