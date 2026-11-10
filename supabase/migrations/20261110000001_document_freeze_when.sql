DROP TRIGGER "bsb_document_freeze" ON "better_supabase"."invoices";

CREATE CONSTRAINT TRIGGER bsb_document_freeze
  AFTER UPDATE OF status ON better_supabase.invoices DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((old.status = 'draft'::text) AND (new.status <> ALL (ARRAY['draft'::text, 'void'::text])) AND (NOT (better_supabase.import_run() IS NOT NULL))))
  EXECUTE FUNCTION better_supabase.freeze_issued_invoice();
