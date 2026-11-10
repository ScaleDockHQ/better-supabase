DROP TRIGGER "bsb_search_drive_node_index" ON "better_supabase"."drive_nodes";

CREATE TRIGGER bsb_search_drive_node_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, archived_at ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('drive_node', 'id');
