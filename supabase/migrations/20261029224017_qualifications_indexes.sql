CREATE INDEX qualifications_evidence_idx ON better_supabase.qualifications USING btree (evidence_attachment_id)
  WHERE (evidence_attachment_id IS NOT NULL);

CREATE INDEX qualifications_type_idx ON better_supabase.qualifications USING btree (tenant_id, type_id);
