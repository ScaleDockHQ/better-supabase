create index concurrently if not exists team_members_tenant_team_idx on better_supabase.team_members using btree (tenant_id, team_id);
