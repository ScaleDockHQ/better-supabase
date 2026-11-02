CREATE INDEX prescriptions_order_idx ON better_supabase.prescriptions USING btree (tenant_id, order_id);
