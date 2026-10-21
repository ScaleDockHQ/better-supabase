"use client";

import type { Result } from "../../../core/result.ts";
import type {
  CheckoutStarted,
  PlanCatalog,
  PlanOption,
  PlanPickerActions,
  PlanPickerSnapshot,
} from "../client.ts";

import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createPlanPickerController } from "../client.ts";

export type { CheckoutStarted, PlanCatalog, PlanOption } from "../client.ts";

export interface UsePlanPickerOptions<P extends { readonly key: string }> {
  /**
   * The plans and the current one, such as a server action; it throws on
   * failure.
   */
  readonly load: () => Promise<PlanCatalog<P>>;
  /** What a server already loaded: the first load is skipped. */
  readonly initial?: PlanCatalog<P>;
  /** A server action that starts Checkout for a plan key and returns its URL. */
  readonly checkout: (plan: string) => Promise<Result<CheckoutStarted>>;
  /**
   * Opens the Checkout URL: `location.assign` on the web,
   * `WebBrowser.openBrowserAsync` in React Native.
   */
  readonly open: (url: string) => void | Promise<void>;
}

export interface PlanPickerState<P>
  extends PlanPickerSnapshot<P>, PlanPickerActions {
  /** The current plan's entry in `plans`. */
  readonly active: P | undefined;
}

/**
 * The plans with the tenant's current one, for a plan picker. `choose` starts
 * Checkout through the server action you pass and opens the URL it returns;
 * Stripe is only ever called on the server. The same hook runs in React DOM and
 * React Native.
 *
 * ```tsx
 * const { plans, current, pending, choose } = usePlanPicker({
 *   load,
 *   checkout,
 *   open,
 * });
 * ```
 */
export function usePlanPicker<P extends { readonly key: string } = PlanOption>(
  options: UsePlanPickerOptions<P>,
): PlanPickerState<P> {
  const { auth } = useBlockEnv();
  const latest = useLatest(options);

  const view = useController(() => {
    const { initial } = latest.current;

    return createPlanPickerController<P>({
      auth,
      load: () => latest.current.load(),
      ...(initial === undefined ? {} : { initial }),
      checkout: (plan) => latest.current.checkout(plan),
      open: (url) => latest.current.open(url),
    });
  }, [auth, latest]).view;

  const active = view.plans?.find((plan) => plan.key === view.current);

  return { ...view, active };
}
