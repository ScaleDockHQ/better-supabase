import type { Block } from "../define-block.ts";
import type { CredentialsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { credentialsEvents } from "./events.ts";
import { credentialsSqlOptions } from "./options.ts";

/** The `credentials` block's manifest (ADR 0029). */
export const credentialsBlock: Block<
  "credentials",
  never,
  never,
  CredentialsEvents
> = defineBlock({
  name: "credentials",
  sql: ["credentials"],
  options: { credentials: credentialsSqlOptions },
  events: credentialsEvents,
  category: "developer",
  entities: {
    credential: {
      mutability: "editable",
      emits: { update: true, delete: true },
    },
  },
  description:
    "Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.",
  recipes: ["connector-setup"],
});
