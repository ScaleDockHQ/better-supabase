ALTER TABLE "better_supabase"."ai_files"
  DROP CONSTRAINT "ai_files_filename_check";

ALTER TABLE "better_supabase"."ai_files"
  ADD CONSTRAINT "ai_files_filename_check"
    CHECK ((((length(filename) >= 1) AND (length(filename) <= 255)) AND (filename !~ '[/\\]'::text) AND (filename <> ALL (ARRAY['.'::text, '..'::text]))));

CREATE INDEX ai_provider_keys_created_by_idx ON better_supabase.ai_provider_keys USING btree (created_by);
