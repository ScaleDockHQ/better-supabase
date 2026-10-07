import { createApiKeys } from "better-supabase/blocks/api-keys";
import { createAuditLog } from "better-supabase/blocks/audit";
import { createComments } from "better-supabase/blocks/comments";
import {
  type RpcClient,
  createOrganizations,
  rpcTransport,
} from "better-supabase/blocks/organizations";
import { createUsage } from "better-supabase/blocks/usage";

import { gettingStarted } from "@/features/onboarding/checklist";
import { settings } from "@/features/settings/settings-definition";

/** `sql.modules.<module>.api` in better-supabase.config.ts. */
const API_SCHEMA = "api";

/**
 * The SQL modules as typed clients over the Data API, acting as the caller
 * of `supabase` (its token, so RLS and each function's checks apply).
 */
export function blocks(supabase: RpcClient) {
  const transport = rpcTransport(supabase, { schema: API_SCHEMA });
  const options = { transport, schema: API_SCHEMA };
  return {
    organizations: createOrganizations(options),
    apiKeys: createApiKeys(options),
    audit: createAuditLog(options),
    comments: createComments(options),
    usage: createUsage(options),
    onboarding: gettingStarted.connect(options),
    settings: settings.connect(options),
    /** A module function without a typed client, such as `flag_enabled`. */
    call: (fn: string, args: Parameters<typeof transport.call>[2]) =>
      transport.call(API_SCHEMA, fn, args),
  };
}
