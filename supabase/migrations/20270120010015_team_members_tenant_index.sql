CREATE INDEX team_members_tenant_team_idx ON better_supabase.team_members USING btree (tenant_id, team_id);
