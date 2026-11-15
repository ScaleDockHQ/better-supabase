-- The entity page for score models first declared a subjectType facet, which wrote
-- an index identical to the block's score_models_subject_idx. The page now declares
-- a filter, so the generated index is gone from the schema file; drop it here.
drop index if exists "better_supabase"."score_models_tenant_id_subject_type_page_idx";
