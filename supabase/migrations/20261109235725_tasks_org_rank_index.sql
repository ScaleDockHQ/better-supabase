CREATE INDEX tasks_organization_id_rank_idx ON public.tasks USING btree (organization_id, rank);
