"use client";

import type { SubmitEvent } from "react";

import {
  useCallback,
  useOptimistic,
  useRef,
  useState,
  useTransition,
} from "react";

import type {
  ActionInputOf,
  ActionResultOf,
  UseActionOptions,
} from "../bindings/client.ts";
import type { DbError } from "../core/errors.ts";

import { fieldErrorsOf } from "../bindings/field-errors.ts";

export type {
  ActionInputOf,
  ActionResultOf,
  UseActionOptions,
} from "../bindings/client.ts";

export interface ActionHandle<I, T> {
  /** Runs the action in a transition; resolves with its result. */
  run(input: I): Promise<ActionResultOf<T>>;
  /** True while a run is in flight, including the router update it causes. */
  readonly pending: boolean;
  /** The inputs of the runs in flight, e.g. to dim one table row. */
  readonly pendingInputs: readonly I[];
  /** The input of the latest run in flight. */
  readonly pendingInput: I | undefined;
  /** The data of the last successful run. */
  readonly data: T | undefined;
  /** The error of the last run, until the next one starts. */
  readonly error: DbError | undefined;
  reset(): void;
}

interface Settled<T> {
  readonly data: T | undefined;
  readonly error: DbError | undefined;
}

const IDLE = { data: undefined, error: undefined } as const;

/**
 * Calls a Server Action from an event handler: tracks pending inputs and the
 * last result, and calls `onSuccess` or `onError`.
 *
 * ```tsx
 * const remove = useAction(removeMember, {
 *   onError: (e) => toast.error(message(e)),
 * });
 * <Button
 *   disabled={remove.pendingInputs.some((p) => p.userId === id)}
 *   onClick={() => remove.run({ userId: id })}
 * />;
 * ```
 */
export function useAction<I, T>(
  action: (input: I) => Promise<ActionResultOf<T>>,
  options: UseActionOptions<ActionInputOf<I>, T> = {},
): ActionHandle<ActionInputOf<I>, T> {
  const [transitioning, startTransition] = useTransition();

  const [inFlight, setInFlight] = useState<
    readonly { readonly input: ActionInputOf<I> }[]
  >([]);

  const [settled, setSettled] = useState<Settled<T>>(IDLE);
  const latest = useRef({ action, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern so `run` stays stable; the react peer range predates useEffectEvent.
  latest.current = { action, options };

  const run = useCallback(
    (input: ActionInputOf<I>): Promise<ActionResultOf<T>> => {
      // Each run gets its own entry, so two runs with equal inputs stay apart.
      const entry = { input };
      setInFlight((current) => [...current, entry]);
      setSettled((current) =>
        current.error === undefined
          ? current
          : { ...current, error: undefined },
      );

      const settledRun = new Promise<ActionResultOf<T>>((resolve, reject) => {
        const done = (): void => {
          setInFlight((current) => current.filter((item) => item !== entry));
        };

        startTransition(async () => {
          let result: ActionResultOf<T>;

          try {
            result = await latest.current.action(input);
          } catch (cause) {
            done();
            reject(cause instanceof Error ? cause : new Error(String(cause)));
            // A throw (not an `ActionResult` error) goes to the error boundary.
            throw cause;
          }

          done();
          setSettled(
            result.ok
              ? { data: result.data, error: undefined }
              : (current) => ({ data: current.data, error: result.error }),
          );
          const { onSuccess, onError } = latest.current.options;

          if (result.ok) {
            onSuccess?.(result.data, input);
          } else {
            onError?.(result.error, input);
          }

          resolve(result);
        });
      });

      // The error boundary reports a throw; callers that ignore the promise
      // should not get an unhandled rejection on top.
      settledRun.catch(() => undefined);

      return settledRun;
    },
    [],
  );

  const reset = useCallback(() => {
    setSettled(IDLE);
  }, []);

  const pendingInputs = inFlight.map((item) => item.input);

  return {
    run,
    pending: transitioning || inFlight.length > 0,
    pendingInputs,
    pendingInput: pendingInputs.at(-1),
    data: settled.data,
    error: settled.error,
    reset,
  };
}

export interface UseOptimisticActionOptions<S, I, T> extends UseActionOptions<
  I,
  T
> {
  /** The confirmed state, usually read from the server render or a query. */
  readonly state: S;
  /** The state the UI shows while the action runs, from the input. */
  readonly update: (state: S, input: I) => S;
}

export interface OptimisticActionHandle<S, I, T> extends ActionHandle<I, T> {
  /**
   * The state to render: `update` applied to the confirmed state for every run
   * in flight. It returns to the confirmed state when the action settles, with
   * the server's answer if the action refreshed it, or the old state if the
   * action failed.
   */
  readonly optimistic: S;
  /** The state as passed, for a "saving" cue next to `optimistic`. */
  readonly confirmed: S;
}

/**
 * `useAction` with an optimistic state (React `useOptimistic`): the UI shows
 * `update(state, input)` at once and falls back to `state` when the run
 * settles, so a failed action undoes itself and a successful one shows what the
 * server returned after the router refresh. Needs React 19.
 *
 * ```tsx
 * const toggle = useOptimisticAction(setDone, {
 *   state: task.done,
 *   update: (_done, input) => input.done,
 * });
 * <Checkbox
 *   checked={toggle.optimistic}
 *   onCheckedChange={(done) => toggle.run({ id, done })}
 * />;
 * ```
 */
export function useOptimisticAction<S, I, T>(
  action: (input: I) => Promise<ActionResultOf<T>>,
  options: UseOptimisticActionOptions<S, ActionInputOf<I>, T>,
): OptimisticActionHandle<S, ActionInputOf<I>, T> {
  const { state, update, ...rest } = options;

  const [optimistic, addOptimistic] = useOptimistic(
    state,
    (current: S, input: ActionInputOf<I>) => update(current, input),
  );

  const latest = useRef({ action, addOptimistic });
  // oxlint-disable-next-line react/refs -- latest-ref pattern so the wrapped action stays stable.
  latest.current = { action, addOptimistic };

  const handle = useAction<I, T>(
    useCallback((input: I) => {
      // `useAction` calls this inside a transition, where React accepts it.
      // SAFETY: `useAction` passes the run's input, whose type is `ActionInputOf<I>`.
      latest.current.addOptimistic(input as ActionInputOf<I>);

      return latest.current.action(input);
    }, []),
    rest,
  );

  return { ...handle, optimistic, confirmed: state };
}

export interface UseActionFormOptions<T> {
  readonly onSuccess?: (data: T, form: HTMLFormElement) => void;
  readonly onError?: (error: DbError, form: HTMLFormElement) => void;
  /** Clear the fields after a successful run. Defaults to true. */
  readonly resetOnSuccess?: boolean;
}

export interface ActionForm<T> {
  /** Spread on the `<form>`. */
  readonly formProps: {
    readonly onSubmit: (event: SubmitEvent<HTMLFormElement>) => void;
  };
  readonly pending: boolean;
  readonly data: T | undefined;
  readonly error: DbError | undefined;
  /** The first message per top-level field of a `validation` error. */
  readonly fieldErrors: Readonly<Partial<Record<string, string>>>;
  reset(): void;
}

/**
 * A `<form>` that submits `FormData` to a Server Action. Fields keep what the
 * user typed when the action fails (a `<form action>` resets them) and clear
 * only on success.
 *
 * ```tsx
 * const form = useActionForm(createCustomer, {
 *   onSuccess: () => toast.success("Saved"),
 * });
 * <form {...form.formProps}>
 *   <Input
 *     name="name"
 *     aria-invalid={form.fieldErrors.name !== undefined}
 *   />
 * </form>;
 * ```
 */
export function useActionForm<T>(
  action: (input: FormData) => Promise<ActionResultOf<T>>,
  options: UseActionFormOptions<T> = {},
): ActionForm<T> {
  const handle = useAction(action);

  return {
    formProps: {
      onSubmit: (event) => {
        event.preventDefault();
        const form = event.currentTarget;
        void handle.run(new FormData(form)).then(
          (result) => {
            if (!result.ok) {
              options.onError?.(result.error, form);

              return result;
            }

            if (options.resetOnSuccess ?? true) {
              form.reset();
            }

            options.onSuccess?.(result.data, form);

            return result;
          },
          () => false,
        );
      },
    },
    pending: handle.pending,
    data: handle.data,
    error: handle.error,
    fieldErrors: fieldErrorsOf(handle.error),
    reset: () => {
      handle.reset();
    },
  };
}
