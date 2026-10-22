"use client";

import { useEffect } from "react";

import type { RecordRef } from "../../../schema/types.ts";
import type { ReactionsActions, ReactionsSnapshot } from "../client.ts";

import { envBlockOptions, envBlockSettings } from "../../block-env-options.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv, useBlockTenant } from "../../react-env.ts";
import { createReactionsController } from "../client.ts";
import { createReactions } from "../reactions.ts";

export interface UseReactionsOptions {
  /** The subjects on screen, at most 200 of each type. */
  readonly subjects: readonly RecordRef[];
  /**
   * The module's realtime topic; `null` loads without listening. Default
   * `blockConfig.reactions.options.topic` from the client's `blocks` config, or
   * `reactions`.
   */
  readonly topic?: string | null;
}

export interface ReactionsState
  extends ReactionsSnapshot, Omit<ReactionsActions, "setSubjects"> {}

/**
 * The reactions of the subjects on screen, keyed by `subjectKey(subject)`
 * (`type:id`), loaded again when anyone in the tenant reacts to one of them.
 * `toggle` feeds an emoji picker. It acts in the client's tenant and calls the
 * schema and function names in the client's `blocks` config, and waits while
 * there is no tenant.
 *
 * ```tsx
 * const { reactions, toggle } = useReactions({
 *   subjects: comments.map((comment) => ({
 *     type: "comment",
 *     id: comment.id,
 *   })),
 * });
 * ```
 */
export function useReactions(options: UseReactionsOptions): ReactionsState {
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const configured = envBlockSettings(env, "reactions")["topic"];

  const topic =
    options.topic === undefined
      ? typeof configured === "string"
        ? configured
        : undefined
      : options.topic;

  const keys = options.subjects
    .map((subject) => `${subject.type}\t${subject.id}`)
    .join("\n");

  const { controller, view } = useController(
    () =>
      createReactionsController({
        client: createReactions({
          ...envBlockOptions(env, "reactions"),
          ...(tenant === undefined ? {} : { tenant }),
        }),
        auth: env.auth,
        ports: env.ports,
        tenant: tenant ?? null,
        subjects: options.subjects,
        ...(topic === undefined ? {} : { topic }),
      }),
    [env, tenant, topic],
  );

  useEffect(() => {
    controller.actions.setSubjects(
      keys === ""
        ? []
        : keys.split("\n").map((line) => {
            const tab = line.indexOf("\t");

            return { type: line.slice(0, tab), id: line.slice(tab + 1) };
          }),
    );
  }, [controller, keys]);

  return view;
}
