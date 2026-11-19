---
"better-supabase": patch
---

Doctor BS213 no longer flags a tenant column that a composite foreign key with not-null columns ties to a parent row, such as `foreign key (job_id, organization_id) references jobs (id, organization_id)`, when every write policy checks one of the key's other columns, such as `j.id = job_parties.job_id` inside an `exists` that checks access to the job.
