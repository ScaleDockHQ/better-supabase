CREATE INDEX IF NOT EXISTS "moderation_notices_item_idx" ON "better_supabase"."moderation_notices" ("item_id");

CREATE INDEX IF NOT EXISTS "moderation_flaggers_user_idx" ON "better_supabase"."moderation_flaggers" ("user_id");

CREATE INDEX IF NOT EXISTS "moderation_appeals_appellant_idx" ON "better_supabase"."moderation_appeals" ("appellant_id");
