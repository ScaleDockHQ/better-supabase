/**
 * Deletes audit entries past the append-only trigger: the tests connect as
 * the owner of `purge_audit_log`, and the setting lasts for this statement.
 */
export const deleteAudit = (where: string): string =>
  `delete from better_supabase.audit_events where (${where}) and (select set_config('better_supabase.audit_purge', 'on', true)) = 'on'`;
