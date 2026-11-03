import type { BlockSqlContext } from "../context.ts";

/**
 * The consent gate of `send_notification`: a notification that names a
 * `consent_purpose` sends nothing, and returns null like a send without
 * recipients, while its subject has no consent in force for the purpose. A
 * notification without a purpose, or without the `consents` block, is not
 * gated.
 */
export function consentGate(ctx: BlockSqlContext): string {
  if (!ctx.installed("consents") || !ctx.of("consents").manages) {
    return "";
  }

  const missing = ctx.of("consents").fn("consent_missing");

  return `
  if nullif(notification ->> 'consent_purpose', '') is not null
    and ${missing}(v_tenant, v_subject_type, v_subject_id, notification ->> 'consent_purpose') then
    return null;
  end if;`;
}
