import {
  type RpcClient,
  createBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { commentsBlock } from "better-supabase/blocks/comments";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import { engagementsBlock } from "better-supabase/blocks/engagements";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { partiesBlock } from "better-supabase/blocks/parties";
import { pipelinesBlock } from "better-supabase/blocks/pipelines";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { savedViewsBlock } from "better-supabase/blocks/saved-views";
import { searchBlock } from "better-supabase/blocks/search";
import { tagsBlock } from "better-supabase/blocks/tags";
import { teamsBlock } from "better-supabase/blocks/teams";

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return createBlocks(
    { transport: rpcTransport(supabase) },
    {
      apiKeys: apiKeysBlock,
      audit: auditBlock,
      billing: billingBlock,
      comments: commentsBlock,
      customFields: customFieldsBlock,
      engagements: engagementsBlock,
      notifications: notificationsBlock,
      organizations: organizationsBlock,
      parties: partiesBlock,
      pipelines: pipelinesBlock,
      profiles: profilesBlock,
      savedViews: savedViewsBlock,
      search: searchBlock,
      tags: tagsBlock,
      teams: teamsBlock,
    },
  );
}
