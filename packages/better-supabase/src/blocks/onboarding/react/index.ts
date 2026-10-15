"use client";

import type { OnboardingActions, OnboardingSnapshot } from "../client.ts";
import type { Checklist, ChecklistScope } from "../onboarding.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createOnboardingController } from "../client.ts";

export interface UseOnboardingOptions {
  /** The organization, for an organization checklist. */
  readonly organizationId?: string | null;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface OnboardingState<Id extends string>
  extends OnboardingSnapshot<Id>, OnboardingActions<Id> {}

/**
 * A checklist's progress for the signed-in user, or for an organization
 * with `organizationId`, through the browser client.
 *
 * ```tsx
 * const { progress, complete } = useOnboarding(gettingStarted, { organizationId });
 * ```
 */
export function useOnboarding<Id extends string, Scope extends ChecklistScope>(
  checklist: Checklist<Id, Scope>,
  options: UseOnboardingOptions = {},
): OnboardingState<Id> {
  const { supabase, auth } = useBlockEnv();
  const { organizationId, schema } = options;
  return useController(
    () =>
      createOnboardingController({
        client: checklist.connect({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        scope: checklist.scope,
        auth,
        organizationId: organizationId ?? null,
      }),
    [checklist, supabase, auth, organizationId, schema],
  ).view;
}
