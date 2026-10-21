"use client";

import { useEffect } from "react";

import type { ReactionsActions, ReactionsSnapshot } from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createReactionsController } from "../client.ts";
import { createReactions } from "../reactions.ts";

export interface UseReactionsOptions {
  readonly organizationId: string;
  readonly subjectType: string;
  /** The subjects on screen, at most 200. */
  readonly subjectIds: readonly string[];
  /**
   * `blockConfig.reactions.options.topic` from `blocks.generated.ts`; `null`
   * loads without listening.
   */
  readonly topic?: string | null;
  /**
   * The schema the calls go to: the module schema (default `better_supabase`),
   * or the API schema from `blocks.<module>.api`.
   */
  readonly schema?: string;
}

export interface ReactionsState
  extends ReactionsSnapshot, Omit<ReactionsActions, "setSubjects"> {}

/**
 * The reactions of the subjects on screen, loaded again when anyone in the
 * organization reacts to one of them. `toggle` feeds an emoji picker.
 *
 * ```tsx
 * const { reactions, toggle } = useReactions({
 *   organizationId,
 *   subjectType: "comment",
 *   subjectIds,
 * });
 * ```
 */
export function useReactions(options: UseReactionsOptions): ReactionsState {
  const { supabase, auth, ports } = useBlockEnv();
  const { organizationId, subjectType, topic, schema } = options;
  const ids = options.subjectIds.join("\n");

  const { controller, view } = useController(
    () =>
      createReactionsController({
        client: createReactions({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        ports,
        organizationId,
        subjectType,
        subjectIds: options.subjectIds,
        ...(topic === undefined ? {} : { topic }),
      }),
    [supabase, auth, ports, organizationId, subjectType, topic, schema],
  );

  useEffect(() => {
    controller.actions.setSubjects(ids === "" ? [] : ids.split("\n"));
  }, [controller, ids]);

  return view;
}
