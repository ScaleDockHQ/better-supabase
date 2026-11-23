import type { InventoryFunction, ResolvedConfig } from "../config/index.ts";
import type { AccessPolicy } from "./tag-statements.ts";

import { parseBsbComment } from "./bsb-tags.ts";
import { modulePermissionKeys } from "./introspect.ts";
import { accessPolicies } from "./tag-statements.ts";

export type ActionKind = "block" | "recordType" | "bucket" | "topic";

/** Where an action's key comes from. */
export type ActionKeySource = "config" | "provider" | "default";

/** One action better-supabase checks and the permission key it resolves to. */
export interface ActionListing {
  readonly kind: ActionKind;
  /** The block instance, record type, bucket or topic. */
  readonly name: string;
  readonly action: string;
  /** `null` when nothing names a key for the action. */
  readonly key: string | null;
  readonly source: ActionKeySource;
}

const BUCKET_ACTIONS = ["read", "list", "write", "delete"] as const;
const TOPIC_ACTIONS = ["receive", "send"] as const;

type ActionMap = Readonly<Record<string, Readonly<Record<string, string>>>>;

function own(value: unknown, key: string): unknown {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }

  return Object.entries(value).find(([name]) => name === key)?.[1];
}

function text(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function resolved(
  kind: ActionKind,
  name: string,
  action: string,
  fromConfig: string | undefined,
  fromProvider: string | undefined,
): ActionListing {
  if (fromConfig !== undefined) {
    return { kind, name, action, key: fromConfig, source: "config" };
  }

  if (fromProvider !== undefined) {
    return { kind, name, action, key: fromProvider, source: "provider" };
  }

  return { kind, name, action, key: null, source: "default" };
}

function blockActions(config: ResolvedConfig): ActionListing[] {
  const actionKeys = config.authorization?.actionKeys;
  const providerBlocks = actionKeys?.blocks;

  return modulePermissionKeys(
    config.blocks,
    config.blockNames,
    config.subjects,
    actionKeys,
  ).map((entry) => {
    const set = own(own(config.blocks, entry.module), "permissions");
    const configured = own(set, entry.action);

    const source: ActionKeySource =
      typeof configured === "string"
        ? "config"
        : providerBlocks?.[entry.module]?.[entry.action] === undefined
          ? "default"
          : "provider";

    return {
      kind: "block",
      name: entry.module,
      action: entry.action,
      key: entry.key,
      source,
    };
  });
}

function recordTypeActions(config: ResolvedConfig): ActionListing[] {
  const provider = config.authorization?.actionKeys?.recordTypes ?? {};

  const types = new Set([
    ...Object.keys(config.subjects),
    ...Object.keys(provider),
  ]);

  return [...types].flatMap((type) => {
    const permissions: Readonly<Record<string, unknown>> =
      config.subjects[type]?.permissions ?? {};

    const actions = new Set([
      ...Object.keys(permissions),
      ...Object.keys(provider[type] ?? {}),
    ]);

    return [...actions].map((action) => {
      const entry = permissions[action];

      const fromConfig = text(entry) ?? text(own(entry, "key"));

      return resolved(
        "recordType",
        type,
        action,
        fromConfig,
        provider[type]?.[action],
      );
    });
  });
}

function bucketActions(config: ResolvedConfig): ActionListing[] {
  const provider: ActionMap = config.authorization?.actionKeys?.buckets ?? {};

  const names = new Set([
    ...Object.keys(config.buckets),
    ...Object.keys(provider),
  ]);

  return [...names].flatMap((bucket) => {
    const access = own(own(config.buckets[bucket], "policy"), "access");

    const actions = new Set<string>([
      ...BUCKET_ACTIONS.filter(
        (action) => typeof own(access, action) === "string",
      ),
      ...Object.keys(provider[bucket] ?? {}),
    ]);

    return [...actions].map((action) => {
      const configured = own(access, action);

      return resolved(
        "bucket",
        bucket,
        action,
        typeof configured === "string" ? configured : undefined,
        provider[bucket]?.[action],
      );
    });
  });
}

function topicActions(config: ResolvedConfig): ActionListing[] {
  const provider: ActionMap = config.authorization?.actionKeys?.topics ?? {};

  const names = new Set([
    ...Object.keys(config.topics),
    ...Object.keys(provider),
  ]);

  return [...names].flatMap((topic) => {
    const actions = new Set<string>([
      ...TOPIC_ACTIONS,
      ...Object.keys(provider[topic] ?? {}),
    ]);

    return [...actions].map((action) =>
      resolved("topic", topic, action, undefined, provider[topic]?.[action]),
    );
  });
}

/**
 * Every action the config makes better-supabase check, per block instance,
 * record type, bucket and topic, with the key it resolves to and whether the
 * config, the authorization provider or the block's default named it.
 */
export function listActions(config: ResolvedConfig): ActionListing[] {
  return [
    ...blockActions(config),
    ...recordTypeActions(config),
    ...bucketActions(config),
    ...topicActions(config),
  ];
}

/** A table comment that may carry `@bsb` tags. */
export interface TaggedComment {
  readonly schema: string;
  readonly name: string;
  readonly comment: string | null;
}

/** A policy a `@bsb access` tag renders. */
export type AccessPolicyListing = AccessPolicy;

/**
 * The policies the `@bsb access` tags in `comments` render, one row each. The
 * generated SQL comes from the same rows (`accessPolicies`).
 */
export function listAccessPolicies(
  config: ResolvedConfig,
  comments: readonly TaggedComment[],
): AccessPolicyListing[] {
  return comments.flatMap((comment) =>
    parseBsbComment(comment.comment).tags.flatMap((tag) =>
      tag.name === "access"
        ? accessPolicies(comment.schema, comment.name, tag, {
            tenantColumn: config.sql.tenantColumn,
          })
        : [],
    ),
  );
}

/** Who calls a function, in the order `listFunctions` checks. */
export type FunctionCaller =
  | "policy"
  | "trigger"
  | "app RPC"
  | "service only"
  | "unreferenced";

/** One function of the read schemas and its caller class. */
export interface FunctionListing {
  readonly schema: string;
  readonly name: string;
  readonly signature: string;
  readonly caller: FunctionCaller;
}

/** The caller classes, in the order the listing prints them. */
export const FUNCTION_CALLERS: readonly FunctionCaller[] = [
  "policy",
  "trigger",
  "app RPC",
  "service only",
  "unreferenced",
];

/**
 * Gives each function one caller class: a policy calls it, a trigger runs it,
 * `anon` or `authenticated` may execute it (app RPC), only `service_role` may
 * (service only), or none of these. A function only other functions call shows
 * as service only or unreferenced; nothing is dropped.
 */
export function listFunctions(
  inventory: readonly InventoryFunction[],
): FunctionListing[] {
  return inventory.map((fn) => ({
    schema: fn.schema,
    name: fn.name,
    signature: fn.signature,
    caller: fn.policy
      ? "policy"
      : fn.trigger
        ? "trigger"
        : fn.execute.includes("anon") || fn.execute.includes("authenticated")
          ? "app RPC"
          : fn.execute.includes("service_role")
            ? "service only"
            : "unreferenced",
  }));
}

/** How many functions of each caller class each schema has. */
export function functionCounts(
  listing: readonly FunctionListing[],
): Record<string, Record<FunctionCaller, number>> {
  const counts: Record<string, Record<FunctionCaller, number>> = {};

  for (const fn of listing) {
    const row = counts[fn.schema] ?? {
      policy: 0,
      trigger: 0,
      "app RPC": 0,
      "service only": 0,
      unreferenced: 0,
    };

    row[fn.caller] += 1;
    counts[fn.schema] = row;
  }

  return counts;
}
