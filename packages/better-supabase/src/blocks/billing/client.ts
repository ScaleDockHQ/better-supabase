import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { err, ok, toDbError } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/**
 * A plan the picker lists: a key from the app's plan catalog, plus whatever the
 * app shows.
 */
export interface PlanOption {
  readonly key: string;
  readonly name: string;
}

/** The plans to offer and the tenant's current plan. */
export interface PlanCatalog<P> {
  readonly plans: readonly P[];
  /** The key of the tenant's current plan, `undefined` without a subscription. */
  readonly current: string | undefined;
}

/**
 * Where Checkout continues: Stripe's hosted page, or `undefined` when the
 * server finished the change itself.
 */
export interface CheckoutStarted {
  readonly url: string | undefined;
}

export interface PlanPickerControllerOptions<
  P extends { readonly key: string } = PlanOption,
> {
  readonly auth: AuthPort;
  /**
   * The plans and the current one, such as a server action that reads the app's
   * plan catalog and the tenant's subscription. It throws on failure.
   */
  readonly load: () => Promise<PlanCatalog<P>>;
  /** What a server already loaded: the first load is skipped. */
  readonly initial?: PlanCatalog<P>;
  /**
   * Starts Checkout for a plan key on the server, such as a server action that
   * calls `billing.checkout()`. The controller never talks to Stripe: the
   * secret key stays on the server.
   */
  readonly checkout: (plan: string) => Promise<Result<CheckoutStarted>>;
  /**
   * Opens the Checkout URL: `location.assign(url)` on the web,
   * `WebBrowser.openBrowserAsync(url)` from `expo-web-browser` in React
   * Native.
   */
  readonly open: (url: string) => void | Promise<void>;
}

export interface PlanPickerSnapshot<P> {
  /** `undefined` until the first load. */
  readonly plans: readonly P[] | undefined;
  readonly current: string | undefined;
  /** The plan whose Checkout is starting. */
  readonly pending: string | undefined;
  readonly error: DbError | undefined;
}

export interface PlanPickerActions {
  /**
   * Starts Checkout for `plan` and opens its URL; a failure is also kept in
   * `error`. Choosing the current plan does nothing.
   */
  readonly choose: (plan: string) => Promise<Result<CheckoutStarted>>;
  readonly refresh: () => Promise<void>;
}

export type PlanPickerController<P> = Controller<
  PlanPickerSnapshot<P>,
  PlanPickerActions
>;

/**
 * The plans with the tenant's current one, for a plan picker: `choose` starts
 * Checkout through the injected server action and opens the URL it returns.
 */
export function createPlanPickerController<
  P extends { readonly key: string } = PlanOption,
>(options: PlanPickerControllerOptions<P>): PlanPickerController<P> {
  return defineController<PlanPickerSnapshot<P>, PlanPickerActions>(
    {
      plans: options.initial?.plans,
      current: options.initial?.current,
      pending: undefined,
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      let seeded = options.initial !== undefined;

      const refresh = async (): Promise<void> => {
        ticket += 1;
        const request = ticket;

        try {
          const catalog = await options.load();

          if (request === ticket) {
            state.set({
              plans: catalog.plans,
              current: catalog.current,
              error: undefined,
            });
          }
        } catch (cause) {
          if (request === ticket) {
            state.set({ error: toDbError(cause) });
          }
        }
      };

      return {
        actions: {
          refresh,
          choose: async (plan) => {
            if (plan === state.get().current) {
              return ok({ url: undefined });
            }

            state.set({ pending: plan, error: undefined });
            let started: Result<CheckoutStarted>;

            try {
              started = await options.checkout(plan);

              if (started.ok && started.data.url !== undefined) {
                await options.open(started.data.url);
              }
            } catch (cause) {
              started = err(toDbError(cause));
            }

            if (!started.ok) {
              state.set({ pending: undefined, error: started.error });

              return started;
            }

            state.set({ pending: undefined });

            if (started.data.url === undefined) {
              await refresh();
            }

            return started;
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            if (seeded) {
              seeded = false;
            } else {
              void refresh();
            }

            return;
          }),
      };
    },
  );
}
