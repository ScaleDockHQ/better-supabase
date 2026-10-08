import type { QueryClient } from "@tanstack/query-core";

import type { QueryKeyOf } from "./queries.ts";

/** A query whose cached data an optimistic update rewrites: any `q.<table>.*()` option. */
export interface OptimisticTarget<T> {
  readonly queryKey: QueryKeyOf<T>;
}

interface MutationContext {
  readonly client: QueryClient;
}

/** What `onMutate` returns: the data each target held before the change. */
export interface OptimisticSnapshot {
  readonly previous: readonly (readonly [
    queryKey: readonly unknown[],
    data: unknown,
  ])[];
}

/**
 * `onMutate`, `onError` and `onSettled` for `useMutation`: spread them next
 * to a mutation option, which keeps its `onSuccess` invalidation.
 */
export interface OptimisticHandlers<V> {
  onMutate(variables: V, context: MutationContext): Promise<OptimisticSnapshot>;
  onError(
    error: unknown,
    variables: V,
    snapshot: OptimisticSnapshot | undefined,
    context: MutationContext,
  ): void;
  onSettled(
    data: unknown,
    error: unknown,
    variables: V,
    snapshot: OptimisticSnapshot | undefined,
    context: MutationContext,
  ): Promise<void>;
}

type Targets<T> = OptimisticTarget<T> | readonly OptimisticTarget<T>[];

function listOf<T>(targets: Targets<T>): readonly OptimisticTarget<T>[] {
  return "queryKey" in targets ? [targets] : targets;
}

/**
 * Rewrites the cached data of `targets` before the mutation runs, puts it
 * back when the mutation fails, and refetches the targets once it settles.
 * `apply` gets the cached data (skipped while nothing is cached) and the
 * mutation's variables.
 */
function rewrite<T, V>(
  targets: Targets<T>,
  apply: (current: T, variables: V) => T,
): OptimisticHandlers<V> {
  const list = listOf(targets);
  return {
    async onMutate(variables, { client }) {
      await Promise.all(
        list.map((target) =>
          client.cancelQueries({ queryKey: target.queryKey, exact: true }),
        ),
      );
      const previous = list.map((target) => {
        const data = client.getQueryData<T>(target.queryKey);
        if (data !== undefined)
          client.setQueryData<T>(target.queryKey, apply(data, variables));
        return [target.queryKey, data] as const;
      });
      return { previous };
    },
    onError(_error, _variables, snapshot, { client }) {
      for (const [queryKey, data] of snapshot?.previous ?? [])
        client.setQueryData(queryKey, data);
    },
    async onSettled(_data, _error, _variables, _snapshot, { client }) {
      await Promise.all(
        list.map((target) =>
          client.invalidateQueries({ queryKey: target.queryKey, exact: true }),
        ),
      );
    },
  };
}

type Keyed<R> = Extract<keyof R, string>;

/**
 * Optimistic updates for list queries (`findMany`), keyed by a row column
 * (`id` by default):
 *
 * - `optimistic.create(list, (input) => row)` adds the row the input will make.
 * - `optimistic.update(list)` merges `{ id, patch }` into the matching row.
 * - `optimistic.remove(list)` drops the row whose key is the deleted id.
 * - `optimistic(target, apply)` rewrites any cached data.
 *
 * ```ts
 * const list = q.todos.findMany({ where: { done: false } });
 * useMutation({ ...q.todos.update(), ...optimistic.update(list) });
 * ```
 */
export const optimistic: (<T, V>(
  targets: Targets<T>,
  apply: (current: T, variables: V) => T,
) => OptimisticHandlers<V>) & {
  create<R, V>(
    targets: Targets<R[]>,
    toRow: (variables: V) => R,
    options?: { readonly position?: "start" | "end" },
  ): OptimisticHandlers<V>;
  update<R, K extends Keyed<R> = Keyed<R> & "id">(
    targets: Targets<R[]>,
    options?: { readonly key?: K },
  ): OptimisticHandlers<{
    readonly id: R[K];
    readonly patch: Partial<R>;
  }>;
  remove<R, K extends Keyed<R> = Keyed<R> & "id">(
    targets: Targets<R[]>,
    options?: { readonly key?: K },
  ): OptimisticHandlers<R[K]>;
} = Object.assign(rewrite, {
  create<R, V>(
    targets: Targets<R[]>,
    toRow: (variables: V) => R,
    options: { readonly position?: "start" | "end" } = {},
  ): OptimisticHandlers<V> {
    return rewrite<R[], V>(targets, (rows, variables) =>
      options.position === "start"
        ? [toRow(variables), ...rows]
        : [...rows, toRow(variables)],
    );
  },
  update<R, K extends Keyed<R>>(
    targets: Targets<R[]>,
    options: { readonly key?: K } = {},
  ): OptimisticHandlers<{ readonly id: R[K]; readonly patch: Partial<R> }> {
    // SAFETY: K defaults to "id"; a row type without it has to pass `key`.
    const key = options.key ?? ("id" as K);
    return rewrite<R[], { readonly id: R[K]; readonly patch: Partial<R> }>(
      targets,
      (rows, { id, patch }) =>
        rows.map((row) => (row[key] === id ? { ...row, ...patch } : row)),
    );
  },
  remove<R, K extends Keyed<R>>(
    targets: Targets<R[]>,
    options: { readonly key?: K } = {},
  ): OptimisticHandlers<R[K]> {
    // SAFETY: K defaults to "id"; a row type without it has to pass `key`.
    const key = options.key ?? ("id" as K);
    return rewrite<R[], R[K]>(targets, (rows, id) =>
      rows.filter((row) => row[key] !== id),
    );
  },
});
