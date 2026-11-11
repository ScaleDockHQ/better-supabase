import {
  createAutomationsAdmin,
  rpcTransport,
} from "better-supabase/blocks/automations";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

import { companyRuleFields, customerRuleFields } from "./rule-fields";

/**
 * Writes the customer field catalog, so the rule editor offers these fields and
 * saved rules are checked against them. A database that is down at start-up
 * leaves the previous catalog in place.
 */
export async function syncRuleFields(): Promise<void> {
  const schema = blockConfig.automations.api;

  const admin = createAutomationsAdmin({
    transport: rpcTransport(bsbCore.admin().$client, { schema }),
    schema,
  });

  for (const fields of [customerRuleFields, companyRuleFields]) {
    // Sequential: each call replaces the catalog of one record type.
    const synced = await admin.syncFields(fields);

    if (!synced.ok) {
      console.warn(`Rule fields not synced: ${synced.error.message}`);
    }
  }
}
