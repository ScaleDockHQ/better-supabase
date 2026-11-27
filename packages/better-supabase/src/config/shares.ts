import type {
  AuthorizationFunctionShare,
  AuthorizationTableShare,
} from "./authorization.ts";
import type { ResolvedConfig } from "./types/config.ts";

/** Where a share entry was declared. */
export type ShareSource = "provider" | "app";

/** One table the provider or the app shares. */
export interface ResolvedTableShare {
  readonly source: ShareSource;
  readonly share: AuthorizationTableShare;
}

/** One function the provider or the app shares. */
export interface ResolvedFunctionShare {
  readonly source: ShareSource;
  readonly share: AuthorizationFunctionShare;
}

/** An app entry the provider already declares with different settings. */
export interface ShareConflict {
  readonly kind: "table" | "function";
  readonly name: string;
}

/** The provider's share entries merged with `shares`. */
export interface ResolvedShares {
  readonly tables: Readonly<Record<string, ResolvedTableShare>>;
  readonly functions: Readonly<Record<string, ResolvedFunctionShare>>;
  /**
   * App entries that disagree with the provider. The maps keep the provider's
   * entry, so gen does not write the app's settings.
   */
  readonly conflicts: readonly ShareConflict[];
}

const sameList = (left: readonly string[], right: readonly string[]): boolean =>
  left.length === right.length &&
  left.every((value, index) => value === right[index]);

const sameTable = (
  left: AuthorizationTableShare,
  right: AuthorizationTableShare,
): boolean =>
  left.share === right.share && sameList(left.permissions, right.permissions);

const sameFunction = (
  left: AuthorizationFunctionShare,
  right: AuthorizationFunctionShare,
): boolean =>
  sameList(left.tables, right.tables) &&
  sameList(left.permissions, right.permissions);

/**
 * The tables and functions a `share: "tenant"` fill may use. The provider's
 * entries come first. An app entry fills a name the provider does not declare.
 * An identical app entry is dropped, so it can be reported as a restated
 * default. An app entry that disagrees is a conflict and is left out, so gen
 * does not write a share the two sides do not agree on.
 */
export function resolveShares(
  config: Pick<ResolvedConfig, "authorization" | "shares">,
): ResolvedShares {
  return {
    tables: merge(
      config.authorization?.tables,
      config.shares?.tables,
      sameTable,
    ).kept,
    functions: merge(
      config.authorization?.sharedFunctions,
      config.shares?.functions,
      sameFunction,
    ).kept,
    conflicts: [
      ...merge(
        config.authorization?.tables,
        config.shares?.tables,
        sameTable,
      ).conflicts.map((name) => ({ kind: "table" as const, name })),
      ...merge(
        config.authorization?.sharedFunctions,
        config.shares?.functions,
        sameFunction,
      ).conflicts.map((name) => ({ kind: "function" as const, name })),
    ],
  };
}

function merge<T>(
  provider: Readonly<Record<string, T>> | undefined,
  app: Readonly<Record<string, T>> | undefined,
  same: (left: T, right: T) => boolean,
): {
  kept: Readonly<Record<string, { source: ShareSource; share: T }>>;
  conflicts: readonly string[];
} {
  const kept: Record<string, { source: ShareSource; share: T }> = {};
  const conflicts: string[] = [];

  for (const [name, share] of Object.entries(provider ?? {})) {
    kept[name] = { source: "provider", share };
  }

  for (const [name, share] of Object.entries(app ?? {})) {
    const existing = kept[name];

    if (existing === undefined) {
      kept[name] = { source: "app", share };
      continue;
    }

    if (!same(existing.share, share)) {
      conflicts.push(name);
    }
  }

  return { kept, conflicts };
}

/** The app entries that repeat the provider's, for the restated-default check. */
export function restatedShares(
  config: Pick<ResolvedConfig, "authorization" | "shares">,
): readonly { readonly path: string; readonly value: unknown }[] {
  return [
    ...samePaths(
      "shares.tables",
      config.authorization?.tables,
      config.shares?.tables,
      sameTable,
    ),
    ...samePaths(
      "shares.functions",
      config.authorization?.sharedFunctions,
      config.shares?.functions,
      sameFunction,
    ),
  ];
}

function samePaths<T>(
  prefix: string,
  provider: Readonly<Record<string, T>> | undefined,
  app: Readonly<Record<string, T>> | undefined,
  same: (left: T, right: T) => boolean,
): { path: string; value: unknown }[] {
  return Object.entries(app ?? {}).flatMap(([name, entry]) => {
    const provided = provider?.[name];

    return provided !== undefined && same(provided, entry)
      ? [{ path: `${prefix}.${name}`, value: entry }]
      : [];
  });
}
