set lock_timeout = '5s';

DROP TRIGGER "bsb_audit" ON "better_supabase"."permission_overrides";

DROP TRIGGER "bsb_audit" ON "better_supabase"."permissions";

DROP TRIGGER "bsb_audit" ON "better_supabase"."platform_roles";

DROP TRIGGER "bsb_audit" ON "better_supabase"."role_permissions";

DROP TRIGGER "bsb_audit" ON "better_supabase"."roles";

ALTER TABLE "better_supabase"."profiles"
  DROP CONSTRAINT "bsb_profiles_username_check";

ALTER TABLE "better_supabase"."profiles"
  ADD CONSTRAINT "bsb_profiles_username_check"
    CHECK
    (((username IS NULL) OR ((length(username) >= 3) AND (length(username) <= 32) AND (username ~* '^[a-z][a-z0-9_]*$'::text) AND (lower(username) <> ALL (ARRAY['admin'::text,
    'administrator'::text,
    'api'::text,
    'app'::text,
    'auth'::text,
    'billing'::text,
    'help'::text,
    'login'::text, 'logout'::text, 'me'::text, 'null'::text, 'root'::text, 'settings'::text, 'signup'::text, 'support'::text, 'system'::text, 'www'::text]))))) NOT VALID;

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.permission_overrides
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"category":"access","tenant_column":"tenant_id"}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.permissions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"category":"access"}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.platform_roles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"category":"access"}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.role_permissions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"category":"access"}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.roles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"category":"access"}');
