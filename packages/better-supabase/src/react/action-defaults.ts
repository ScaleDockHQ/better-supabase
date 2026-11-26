import type { Context, ReactNode } from "react";

import { createContext, createElement } from "react";

import type { ActionResultOf } from "../bindings/client.ts";

/** A whole outcome, with the fields the app's `actions.envelope` adds. */
export type ActionOutcome = ActionResultOf<unknown> &
  Readonly<Record<string, unknown>>;

export interface ActionDefaults {
  /** Runs after a success of a call that has no `onSuccess` of its own. */
  readonly onSuccess?: (outcome: ActionOutcome, input: unknown) => void;
  /** Runs after an error of a call that has no `onError` of its own. */
  readonly onError?: (outcome: ActionOutcome, input: unknown) => void;
}

export const ActionDefaultsContext: Context<ActionDefaults | null> =
  createContext<ActionDefaults | null>(null);

/**
 * App-wide `onSuccess` and `onError` for `useAction`, `useOptimisticAction` and
 * `useActionForm`, for toasts. They receive the whole outcome, so the fields of
 * `NextOptions.actions.envelope` (a `message`, `fieldErrors`) are there.
 */
export function ActionDefaultsProvider({
  value,
  children,
}: {
  readonly value: ActionDefaults;
  readonly children: ReactNode;
}): ReactNode {
  return createElement(ActionDefaultsContext, { value }, children);
}
