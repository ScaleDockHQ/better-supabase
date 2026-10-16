import type { DbError } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  Checklist,
  ChecklistProgress,
  ChecklistScope,
  ChecklistSubject,
} from "./onboarding.ts";

import { defineController, whileSignedIn } from "../controller.ts";

/** The calls the controller makes for one checklist; `createOnboarding` fits. */
export interface OnboardingControllerClient<
  Id extends string,
  Scope extends ChecklistScope,
> {
  progress(
    checklist: Checklist<Id, Scope>,
    ...subject: ChecklistSubject<Scope>
  ): AsyncResult<ChecklistProgress<Id>>;
  complete(
    checklist: Checklist<Id, Scope>,
    step: Id,
    ...subject: ChecklistSubject<Scope>
  ): AsyncResult<boolean>;
  reset(
    checklist: Checklist<Id, Scope>,
    step: Id,
    ...subject: ChecklistSubject<Scope>
  ): AsyncResult<boolean>;
}

export interface OnboardingControllerOptions<
  Id extends string,
  Scope extends ChecklistScope,
> {
  /** `createOnboarding({ transport })`. */
  readonly client: OnboardingControllerClient<Id, Scope>;
  /** The checklist, from `defineChecklist`. */
  readonly checklist: Checklist<Id, Scope>;
  readonly auth: AuthPort;
  /** The organization, for an organization checklist; it waits without one. */
  readonly organizationId?: string | null;
}

export interface OnboardingSnapshot<Id extends string> {
  /** `undefined` until the first load. */
  readonly progress: ChecklistProgress<Id> | undefined;
  readonly error: DbError | undefined;
}

export interface OnboardingActions<Id extends string> {
  /** Marks a step done, then loads the progress again. */
  readonly complete: (step: Id) => Promise<void>;
  readonly reset: (step: Id) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

export type OnboardingController<Id extends string> = Controller<
  OnboardingSnapshot<Id>,
  OnboardingActions<Id>
>;

/** A checklist's progress for the signed-in user, or for an organization. */
export function createOnboardingController<
  Id extends string,
  Scope extends ChecklistScope,
>(options: OnboardingControllerOptions<Id, Scope>): OnboardingController<Id> {
  const { client, checklist } = options;
  const organizationId = options.organizationId ?? null;
  const ready = checklist.scope === "user" || organizationId !== null;
  // SAFETY: ChecklistSubject is [organizationId] for organization checklists and [] for user ones.
  const subject = (
    checklist.scope === "organization" && organizationId !== null
      ? [organizationId]
      : []
  ) as ChecklistSubject<Scope>;
  return defineController<OnboardingSnapshot<Id>, OnboardingActions<Id>>(
    { progress: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        const run = state.run();
        const result = await client.progress(checklist, ...subject);
        if (run !== state.run()) return;
        state.set(
          result.ok
            ? { progress: result.data, error: undefined }
            : { error: result.error },
        );
      };
      const change = async (
        action: "complete" | "reset",
        step: Id,
      ): Promise<void> => {
        const result = await client[action](checklist, step, ...subject);
        if (result.ok) await refresh();
        else state.set({ error: result.error });
      };
      return {
        actions: {
          refresh,
          complete: (step) => change("complete", step),
          reset: (step) => change("reset", step),
        },
        start: () =>
          ready
            ? whileSignedIn(options.auth, () => {
                void refresh();
                return;
              })
            : undefined,
      };
    },
  );
}
