create unique index concurrently if not exists bsb_attachments_tenant_id_key on better_supabase.attachments using btree (tenant_id, id);
