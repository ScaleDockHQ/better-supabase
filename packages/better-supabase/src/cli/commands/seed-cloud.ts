import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { SeedDefaultsFunction } from "../../sql/index.ts";
import type { ConsentRequest } from "../core/agent.ts";
import type { CommandResult } from "../core/io.ts";
import type { connect } from "../db.ts";
import type { CliEnv } from "../env.ts";
import type { Fetch } from "../seeds/cloud.ts";
import type { SampleRequest } from "../seeds/contract.ts";

import {
  moduleLayout,
  seedDefaultsFunctions,
  tenantsQuery,
} from "../../sql/index.ts";
import { databaseUrl } from "../config.ts";
import { databaseHost, isLocalDatabaseUrl } from "../core/agent.ts";
import { insideRoot } from "../core/files.ts";
import { display } from "../core/io.ts";
import {
  CloudError,
  activeLogin,
  requestSample,
  tokenPath,
} from "../seeds/cloud.ts";
import { cloudFailure, cloudUrl } from "./account.ts";

/** What `db seed --defaults` and `--sample` read from the flags. */
export interface CloudSeedFlags {
  readonly tenant?: string | undefined;
  readonly variant?: readonly string[] | string | undefined;
  readonly locale?: string | undefined;
  readonly size?: string | undefined;
  readonly seed?: string | undefined;
  readonly "demo-org"?: boolean | undefined;
  readonly out?: string | undefined;
  readonly stack?: string | undefined;
  readonly "dry-run"?: boolean | undefined;
  readonly check?: boolean | undefined;
}

type DefaultsCall = SeedDefaultsFunction;

const defaultsCalls = seedDefaultsFunctions;

/** `--variant block=name` (repeatable) over `database.seed.defaults.variants`. */
export function resolveVariants(
  config: ResolvedConfig,
  flag: CloudSeedFlags["variant"],
  calls: readonly DefaultsCall[],
): { variants: Record<string, string> } | { error: string } {
  const variants: Record<string, string> = { ...config.seed.defaults.variants };

  const given = flag === undefined ? [] : [flag].flat();

  for (const entry of given) {
    const at = entry.indexOf("=");

    if (at < 1) {
      return { error: `--variant takes block=name, not "${entry}".` };
    }

    variants[entry.slice(0, at)] = entry.slice(at + 1);
  }

  for (const [block, variant] of Object.entries(variants)) {
    const call = calls.find((entry) => entry.module === block);

    if (call === undefined) {
      return {
        error: `Variant ${block}=${variant}: ${block} declares no tenant defaults.`,
      };
    }

    if (!call.variants.includes(variant)) {
      return {
        error: `Variant ${block}=${variant}: ${block} knows ${call.variants.length === 0 ? "no variants" : call.variants.join(", ")}.`,
      };
    }
  }

  return { variants };
}

interface TenantRow {
  readonly id: string;
  readonly slug: string | null;
  readonly name: string | null;
}

/**
 * `db seed --defaults`: calls each installed module's `seed_<module>_defaults`
 * for one organization (or every one), so existing organizations get the rows
 * their blocks gained later. Rows that exist are kept.
 */
export async function runSeedDefaults(
  config: ResolvedConfig,
  args: CloudSeedFlags,
  env: CliEnv,
  open: typeof connect,
  dbUrl: string | undefined,
  requireConsent: (request: ConsentRequest) => void,
): Promise<CommandResult> {
  const calls = defaultsCalls(config);

  if (calls.length === 0) {
    return {
      code: 0,
      output: "No installed block declares tenant defaults.",
      data: { modules: [], tenants: [], applied: false },
    };
  }

  const resolved = resolveVariants(config, args.variant, calls);

  if ("error" in resolved) {
    return { code: 1, errorCode: "invalid_input", error: resolved.error };
  }

  const tenant = args.tenant ?? "*";
  const query = tenantsQuery(moduleLayout(config), config.blockNames, tenant);

  if (query === undefined) {
    return {
      code: 1,
      errorCode: "invalid_input",
      error:
        "seed --defaults looks organizations up in the organizations block. Add it with `better-supabase add organizations`.",
    };
  }

  const locale = args.locale ?? config.seed.defaults.locale;
  const modules = calls.map((call) => call.module);

  if (args["dry-run"] === true || args.check === true) {
    return {
      code: 0,
      output: `Would seed the defaults of ${modules.join(", ")} for ${tenant === "*" ? "every organization" : tenant} in ${locale}.`,
      data: { modules, tenants: [], applied: false, locale },
    };
  }

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BSB_STACK,
  );

  if (!isLocalDatabaseUrl(url)) {
    requireConsent({
      effect: "database-write",
      detail: `seed --defaults inserts rows into ${databaseHost(url)}`,
    });
  }

  const { client, close } = await open(url);
  let labels: string[];

  try {
    const found = await client.query<TenantRow>(query.text, [...query.values]);

    if (found.rows.length === 0) {
      return {
        code: 1,
        errorCode: "not_found",
        error:
          tenant === "*"
            ? "There are no organizations to seed."
            : `No organization has the slug or id "${tenant}".`,
      };
    }

    await client.query("begin");

    try {
      for (const row of found.rows) {
        for (const call of calls) {
          await client.query(`select ${call.fn}($1, $2, $3)`, [
            row.id,
            resolved.variants[call.module] ?? null,
            locale,
          ]);
        }
      }

      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    }

    labels = found.rows.map((row) => row.slug ?? row.id);
  } finally {
    await close();
  }

  return {
    code: 0,
    output: `Seeded the defaults of ${modules.join(", ")} for ${labels.join(", ")} (existing rows were kept).`,
    data: { modules, tenants: labels, applied: true, locale },
  };
}

/** The request `db seed --sample` posts, from the config and the flags. */
export function sampleRequest(
  config: ResolvedConfig,
  args: CloudSeedFlags,
  variants: Readonly<Record<string, string>>,
): SampleRequest | { error: string } {
  const size = args.size ?? config.seed.sample.size;

  if (size !== "s" && size !== "m" && size !== "l") {
    return { error: `--size is s, m or l, not "${size}".` };
  }

  const seed =
    args.seed === undefined ? config.seed.sample.seed : Number(args.seed);

  if (!Number.isInteger(seed)) {
    return { error: `--seed is a whole number, not "${args.seed}".` };
  }

  const demo = args["demo-org"] === true;

  if (demo && args.tenant !== undefined) {
    return { error: "Pass --tenant or --demo-org, not both." };
  }

  if (!demo && args.tenant === undefined) {
    return { error: "Say where the data goes: --tenant <slug> or --demo-org." };
  }

  return {
    design: { blocks: config.blockNames },
    ...(typeof config.preset === "string" ? { preset: config.preset } : {}),
    instances: Object.keys(config.instances),
    variants,
    locale: args.locale ?? config.seed.sample.locale,
    size,
    seed,
    target: demo ? "demoOrg" : "tenant",
    ...(args.tenant === undefined ? {} : { tenant: args.tenant }),
  };
}

export interface SampleTools {
  readonly fetch: Fetch;
  readonly now: () => number;
}

/**
 * `db seed --sample`: asks the cloud for statements and applies them in one
 * transaction, or writes them to `--out`. Needs `better-supabase login` and a
 * plan with sample data; a 402 names the upgrade page.
 */
export async function runSeedSample(
  config: ResolvedConfig,
  args: CloudSeedFlags,
  env: CliEnv,
  tools: SampleTools,
  open: typeof connect,
  dbUrl: string | undefined,
  requireConsent: (request: ConsentRequest) => void,
): Promise<CommandResult> {
  const resolved = resolveVariants(config, args.variant, defaultsCalls(config));

  if ("error" in resolved) {
    return { code: 1, errorCode: "invalid_input", error: resolved.error };
  }

  const request = sampleRequest(config, args, resolved.variants);

  if ("error" in request) {
    return { code: 1, errorCode: "invalid_input", error: request.error };
  }

  let login: Awaited<ReturnType<typeof activeLogin>>;

  try {
    login = await activeLogin(
      tokenPath(env),
      tools.fetch,
      cloudUrl(env),
      tools.now(),
    );
  } catch (error) {
    return cloudFailure(error);
  }

  if (login === undefined) {
    return cloudFailure(
      new CloudError("unauthorized", "Not logged in", { status: 401 }),
    );
  }

  let sample: Awaited<ReturnType<typeof requestSample>>;

  try {
    sample = await requestSample(
      tools.fetch,
      cloudUrl(env),
      login.accessToken,
      request,
    );
  } catch (error) {
    return cloudFailure(error);
  }

  const data = {
    summary: sample.summary,
    statements: sample.statements.length,
    estimatedRows: sample.estimatedRows,
    target: request.target,
  };

  if (args.out !== undefined) {
    const path = insideRoot(config.root, args.out, "--out");

    await mkdir(dirname(resolve(config.root, path)), { recursive: true });
    await writeFile(
      resolve(config.root, path),
      `-- Generated by \`better-supabase db seed --sample\` (seed ${String(request.seed)}, size ${request.size}). Do not edit.\n\n${sample.statements.join("\n\n")}\n`,
    );

    return {
      code: 0,
      output: `${sample.summary}\nWrote ${sample.statements.length} statements to ${display(config.root, path)}.`,
      data: { ...data, file: display(config.root, path), applied: false },
    };
  }

  if (args["dry-run"] === true || args.check === true) {
    return {
      code: 0,
      output: `${sample.summary}\nWould apply ${sample.statements.length} statements (about ${String(sample.estimatedRows)} rows).`,
      data: { ...data, applied: false },
    };
  }

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BSB_STACK,
  );

  if (!isLocalDatabaseUrl(url)) {
    requireConsent({
      effect: "database-write",
      detail: `seed --sample inserts about ${String(sample.estimatedRows)} rows into ${databaseHost(url)}`,
    });
  }

  const { client, close } = await open(url);

  try {
    await client.query("begin");

    try {
      for (const statement of sample.statements) {
        await client.query(statement);
      }

      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    }
  } finally {
    await close();
  }

  return {
    code: 0,
    output: `${sample.summary}\nApplied ${sample.statements.length} statements (about ${String(sample.estimatedRows)} rows).`,
    data: { ...data, applied: true },
  };
}
