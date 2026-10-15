import {
  type RpcClient,
  createBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { apiKeysBlock } from "better-supabase/blocks/api-keys";
import { auditBlock } from "better-supabase/blocks/audit";
import { billingBlock } from "better-supabase/blocks/billing";
import { bookingsBlock } from "better-supabase/blocks/bookings";
import { calendarBlock } from "better-supabase/blocks/calendar";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { organizationsBlock } from "better-supabase/blocks/organizations";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { remindersBlock } from "better-supabase/blocks/reminders";
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
      bookings: bookingsBlock,
      calendar: calendarBlock,
      notifications: notificationsBlock,
      organizations: organizationsBlock,
      profiles: profilesBlock,
      reminders: remindersBlock,
      teams: teamsBlock,
    },
  );
}
