DROP TRIGGER "bsb_realtime_delete" ON "better_supabase"."maintenance_requests";

DROP TRIGGER "bsb_realtime_insert" ON "better_supabase"."maintenance_requests";

DROP TRIGGER "bsb_realtime_update" ON "better_supabase"."maintenance_requests";

DROP TRIGGER "bsb_realtime_delete" ON "better_supabase"."work_items";

DROP TRIGGER "bsb_realtime_insert" ON "better_supabase"."work_items";

DROP TRIGGER "bsb_realtime_update" ON "better_supabase"."work_items";

CREATE INDEX ai_chat_participants_chat_idx ON better_supabase.ai_chat_participants USING btree (chat_id);

CREATE INDEX ai_chat_participants_customer_user_idx ON better_supabase.ai_chat_participants USING btree (customer_user_id);
