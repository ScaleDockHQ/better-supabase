import { createRulesAdmin, rpcTransport } from "better-supabase/blocks/rules";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

import { customerRuleFields } from "./rule-fields";

/**
 * Writes the customer field catalog, so the rule editor offers these fields and
 * saved rules are checked against them. A database that is down at start-up
 * leaves the previous catalog in place.
 */
export async function syncRuleFields(): Promise<void> {
  const schema = blockConfig.rules.api;

  const admin = createRulesAdmin({
    transport: rpcTransport(bsb.admin().$client, { schema }),
    schema,
  });

  const synced = await admin.syncFields(customerRuleFields);

  if (!synced.ok) {
    console.warn(`Rule fields not synced: ${synced.error.message}`);
  }
}
