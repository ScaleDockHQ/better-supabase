import type { ResolvedConfig } from "../../config/index.ts";
import type {
  ModuleAccessProvider,
  ModuleLayout,
  ModuleEntitlementsProvider,
} from "../../sql/index.ts";
import type { SqlFlags } from "./args.ts";

import {
  moduleLayout,
  modulePermissionKeys,
  resolveModules,
} from "../../sql/index.ts";
import {
  accessProviderMode,
  entitlementsMode,
  moduleKeyProblems,
} from "../authorization.ts";
import { compiledReadSets } from "../read-sets.ts";
import { moduleLayoutFor, schemasDirOf } from "../sql-layout.ts";

/** Modules that fill the `memberships` claim, which a provider's hook may own. */
export const MEMBERSHIP_CLAIM_MODULES: ReadonlySet<string> = new Set([
  "tenant",
]);

/**
 * Whether the provider's access token hook writes the `memberships` claim
 * itself.
 */
export const providerOwnsMemberships = (config: ResolvedConfig): boolean =>
  config.authorization?.tokenHook?.ownedClaims.includes("memberships") ?? false;

/**
 * The provider's memberships for the `entitlements` module. When `names`
 * resolve to that module, an invalid mode (no provider, a scope it lacks, an
 * unknown id type) throws instead of falling back to the tenant module. Without
 * `names` (`sql list`) it only describes the modules, so it doesn't.
 */
function entitlementsProviderFor(
  config: ResolvedConfig,
  names?: readonly string[],
): ModuleEntitlementsProvider | undefined {
  const mode = entitlementsMode(config);

  switch (mode.kind) {
    case "tenant": {
      return undefined;
    }

    case "provider": {
      return mode.provider;
    }

    case "invalid": {
      if (
        names === undefined ||
        !resolveModules(names, {}).some(
          (module) => module.name === "entitlements",
        )
      ) {
        return undefined;
      }

      throw new TypeError(mode.problem);
    }

    default: {
      const unreachable: never = mode;

      return unreachable;
    }
  }
}

/**
 * The provider for the `access` module's `provider` model. When `names` resolve
 * to `access`, an invalid mode throws, and so does a module permission key the
 * provider doesn't mark `sqlComplete: true`. `sql list` (no `names`) doesn't
 * render, so it doesn't throw.
 */
function accessProviderFor(
  config: ResolvedConfig,
  names?: readonly string[],
): ModuleAccessProvider | undefined {
  const mode = accessProviderMode(config);

  const renders =
    names !== undefined &&
    resolveModules(names, {}).some((module) => module.name === "access");

  switch (mode.kind) {
    case "off": {
      return undefined;
    }

    case "provider": {
      if (!renders || !config.authorization) {
        return mode.access;
      }

      const problems = moduleKeyProblems(
        config.authorization,
        modulePermissionKeys(config.blocks, names),
      );

      if (problems.length > 0) {
        throw new TypeError(
          problems.map((problem) => problem.message).join("\n"),
        );
      }

      return mode.access;
    }

    case "invalid": {
      if (!renders) {
        return undefined;
      }

      throw new TypeError(mode.problem);
    }

    default: {
      const unreachable: never = mode;

      return unreachable;
    }
  }
}

/** The provider's permission keys, for `api-keys` scopes. */
const permissionKeysFor = (
  config: ResolvedConfig,
): readonly string[] | undefined =>
  config.authorization?.permissions?.map((permission) => permission.key);

export async function layout(
  config: ResolvedConfig,
  args: SqlFlags,
  names?: readonly string[],
): Promise<ModuleLayout> {
  return {
    ...moduleLayout(
      config,
      args["tests-dir"],
      [],
      entitlementsProviderFor(config, names),
      accessProviderFor(config, names),
      permissionKeysFor(config),
    ),
    schemasDir: await schemasDirOf(config),
  };
}

/**
 * The layout, with `config.readSets` compiled when `names` includes
 * `read-sets`.
 */
export async function layoutFor(
  config: ResolvedConfig,
  args: SqlFlags,
  names: readonly string[],
): Promise<ModuleLayout> {
  const entitlementsProvider = entitlementsProviderFor(config, names);

  const resolved = new Set(
    resolveModules(
      names,
      entitlementsProvider ? { entitlementsProvider } : {},
    ).map((module) => module.name),
  );

  const accessProvider = accessProviderFor(config, names);

  return moduleLayoutFor(config, {
    names,
    testsDir: args["tests-dir"],
    readSets: resolved.has("read-sets") ? await compiledReadSets(config) : [],
    ...(entitlementsProvider ? { entitlementsProvider } : {}),
    ...(accessProvider ? { accessProvider } : {}),
    permissionCatalog: permissionKeysFor(config),
  });
}
