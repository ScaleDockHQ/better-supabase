"use client";

import type { AnnouncementsActions, AnnouncementsSnapshot } from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createAnnouncements } from "../announcements.ts";
import { createAnnouncementsController } from "../client.ts";

export interface UseAnnouncementsOptions {
  /** The active tenant, for tenant, role and plan audiences. */
  readonly organizationId?: string | null;
  /** The topic the module broadcasts to (`blocks.announcements.options.topic`); `null` loads once. */
  readonly topic?: string | null;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface AnnouncementsState
  extends AnnouncementsSnapshot, AnnouncementsActions {}

/**
 * The signed-in user's live announcements, loaded again whenever staff
 * publish, change or remove one.
 *
 * ```tsx
 * const { items, dismiss } = useAnnouncements({ organizationId });
 * ```
 */
export function useAnnouncements(
  options: UseAnnouncementsOptions = {},
): AnnouncementsState {
  const { supabase, auth, ports } = useBlockEnv();
  const { organizationId, topic, schema } = options;
  return useController(
    () =>
      createAnnouncementsController({
        client: createAnnouncements({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        ports,
        ...(organizationId === undefined ? {} : { organizationId }),
        ...(topic === undefined ? {} : { topic }),
      }),
    [supabase, auth, ports, organizationId, topic, schema],
  ).view;
}
