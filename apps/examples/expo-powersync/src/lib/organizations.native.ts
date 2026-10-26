import type { OrganizationMembership } from "better-supabase/blocks/organizations";

import {
  createOrganizations,
  rpcTransport,
} from "better-supabase/blocks/organizations";
import { powersyncMembershipsTransport } from "better-supabase/powersync";

import { API_SCHEMA } from "./blocks";
import { powersync } from "./powersync/database";
import { supabase } from "./supabase/supabase.native";

/**
 * The caller's organizations from the synced `memberships` and `organizations`
 * tables, so the switcher lists them offline. Switching still goes to the Data
 * API, which refreshes the tenant claim.
 */
const organizations = createOrganizations({
  transport: powersyncMembershipsTransport(powersync, {
    server: rpcTransport(supabase),
  }),
  schema: API_SCHEMA,
});

export async function loadOrganizations(): Promise<
  readonly OrganizationMembership[]
> {
  return organizations.mine().orThrow();
}
