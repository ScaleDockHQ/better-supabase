CREATE INDEX tasks_project_id_organization_id_idx ON public.tasks USING btree (project_id, organization_id);
