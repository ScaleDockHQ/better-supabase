"use client";

import type { ReactNode } from "react";

import { useOffline } from "next/offline.js";
import { createElement, useEffect } from "react";

import type {
  BlockArgsOf,
  BlockDataOf,
  BlockEngineOptions,
  BlockMethodName,
  BlockQueryOptions,
} from "../../blocks/block-controller.ts";
import type {
  BlockOfflineMutationActions,
  BlockOfflineMutationState,
  BlockOfflineQueryActions,
  BlockOfflineQueryState,
} from "../../blocks/block-offline.ts";

import { blockArgsKey } from "../../blocks/block-controller.ts";
import {
  createOfflineBlockMutation,
  createOfflineBlockQuery,
} from "../../blocks/block-offline.ts";
import { useController } from "../../blocks/react-controller.ts";
import { OfflineContext } from "../../react/offline.ts";

/**
 * `useBlockQuery` that pauses while the app is offline (`useOffline()` from
 * `next/offline`): the last data stays, `offline` is `true` instead of an
 * error, and the read runs once when the connection returns. `useOffline()` is
 * `false` during SSR and hydration, so the first render matches the server.
 */
export function useBlockQuery<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  args: BlockArgsOf<C, K>,
  options: BlockQueryOptions = {},
): BlockOfflineQueryState<BlockDataOf<C, K>> & BlockOfflineQueryActions {
  const offline = useOffline();

  const { controller, view } = useController(
    () =>
      createOfflineBlockQuery(client, method, args, { ...options, offline }),
    [
      client,
      method,
      blockArgsKey(args),
      options.refetchOn?.source,
      options.engine,
      options.engine === undefined ? undefined : options.instance,
    ],
  );

  useEffect(() => {
    controller.actions.setOffline(offline);
  }, [controller, offline]);

  return view;
}

/**
 * `useBlockMutation` that queues one write while the app is offline and runs it
 * once when the connection returns, the way `experimental.useOffline` retries a
 * Server Action. `mutate` resolves with the write's own result.
 */
export function useBlockMutation<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  options: BlockEngineOptions = {},
): BlockOfflineMutationState<BlockDataOf<C, K>> &
  BlockOfflineMutationActions<BlockArgsOf<C, K>, BlockDataOf<C, K>> {
  const offline = useOffline();

  const { controller, view } = useController(
    () => createOfflineBlockMutation(client, method, { ...options, offline }),
    [
      client,
      method,
      options.engine,
      options.engine === undefined ? undefined : options.instance,
    ],
  );

  useEffect(() => {
    controller.actions.setOffline(offline);
  }, [controller, offline]);

  return view;
}

/**
 * Tells the data hooks and `RecordProvider` below it whether the app is
 * offline, from `useOffline()`. Put it once inside `BetterSupabaseProvider`.
 */
export function OfflineBoundary(props: {
  readonly children?: ReactNode;
}): ReactNode {
  return createElement(OfflineContext, { value: useOffline() }, props.children);
}
