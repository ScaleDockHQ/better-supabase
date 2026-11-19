create unique index concurrently if not exists bsb_teams_tenant_id_key on better_supabase.teams using btree (tenant_id, id);
