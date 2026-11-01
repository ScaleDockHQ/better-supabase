CREATE INDEX putaway_rules_location_idx ON better_supabase.putaway_rules USING btree (location_id);

CREATE INDEX putaway_rules_variant_idx ON better_supabase.putaway_rules USING btree (variant_id);
