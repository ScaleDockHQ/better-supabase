import { readFile } from "node:fs/promises";

import type { Fingerprint } from "./catalog.ts";
import type { BaselineContext } from "./stack.ts";

import { CliError } from "../core/errors.ts";
import { connect } from "../db.ts";
import { loadPgDelta, migrationFiles, openPgPool } from "../in-stack-diff.ts";
import { supabaseDir } from "../supabase-config.ts";
import { VERSION } from "../version.ts";
import { applyBaseline } from "./apply.ts";
import { baselineRoot, findArtifact } from "./artifact.ts";
import {
  catalogFingerprint,
  extractCatalog,
  fingerprintDiff,
  planSql,
  serverVersion,
  tableSignatures,
} from "./catalog.ts";
import { hashFiles } from "./key.ts";
import { EMPTY_START_ENV, cliVersion, startScratch } from "./stack.ts";

const VERIFY_STACK = "bsb-baseline-verify";

export interface VerifyOptions {
  readonly out?: string | undefined;
  readonly withSeed: boolean;
}

export interface VerifyResult {
  readonly key: string;
  readonly schemaActions: number;
  readonly fingerprintMatches: boolean;
  readonly mismatchedCounts: readonly string[];
}

/**
 * Restores the current baseline into a fresh stack and compares it with the
 * replay it was built from: the diff engine plans nothing from the restored
 * catalog to the stored one, the policy, trigger, grant and function digest
 * matches, and the restored tables hold the recorded row counts.
 */
export async function verifyBaseline(
  ctx: BaselineContext,
  options: VerifyOptions,
): Promise<VerifyResult> {
  const { root } = ctx;
  const dir = supabaseDir(root);

  const [current, delta] = await Promise.all([
    migrationFiles(root, dir).then((files) => hashFiles(root, files)),
    loadPgDelta(),
  ]);

  const stack = await startScratch(ctx, VERIFY_STACK, EMPTY_START_ENV);

  try {
    const { client, close } = await connect(stack.dbUrl);
    let postgres: string;

    try {
      postgres = await serverVersion(client);
    } finally {
      await close();
    }

    const search = await findArtifact(
      baselineRoot(root, options.out),
      current,
      {
        bsb: VERSION,
        supabaseCli: await cliVersion(ctx),
        postgres,
        engine: delta.ENGINE_VERSION,
      },
    );

    if (search.found === undefined || search.found.match.pending.length > 0) {
      throw new CliError(
        "not_found",
        `No baseline covers the current migrations: ${search.reason}. Run baseline build first.`,
      );
    }

    const { found } = search;

    const applied = await applyBaseline(ctx, {
      from: options.out,
      withSeed: options.withSeed,
      target: {
        dbUrl: stack.dbUrl,
        storage:
          stack.apiUrl !== undefined && stack.serviceKey !== undefined
            ? { apiUrl: stack.apiUrl, serviceKey: stack.serviceKey }
            : undefined,
        migrate: () => Promise.resolve({ code: 0, stdout: "", stderr: "" }),
      },
    });

    if (applied.mode !== "baseline") {
      throw new CliError(
        "check_failed",
        `The baseline did not load: ${applied.reason ?? "unknown reason"}.`,
      );
    }

    const snapshot = delta.deserializeSnapshot(
      await readFile(
        options.withSeed ? found.files.seedSnapshot : found.files.snapshot,
        "utf-8",
      ),
    );

    const restored = await withRestored(stack.dbUrl, delta);

    const plan = planSql(
      delta,
      restored.extracted,
      { facts: snapshot.factBase, pgVersion: snapshot.pgVersion },
      restored.planOptions,
    );

    const expected = {
      ...found.manifest.counts,
      ...(options.withSeed ? found.manifest.seed?.counts : {}),
    };

    const mismatchedCounts = Object.entries(expected)
      .filter(
        ([table, count]) =>
          Number(restored.signatures.get(table)?.split(":")[0] ?? -1) !== count,
      )
      .map(
        ([table, count]) =>
          `${table} (${String(count)} expected, ${restored.signatures.get(table)?.split(":")[0] ?? "missing"} restored)`,
      );

    const differing = fingerprintDiff(
      (options.withSeed
        ? found.manifest.seed?.fingerprint
        : found.manifest.fingerprint) ?? {},
      restored.fingerprint,
    );

    const fingerprintMatches = differing.length === 0;

    const problems = [
      ...(plan.actions === 0
        ? []
        : [
            `pg-delta still plans ${String(plan.actions)} action(s), e.g. ${plan.sql.split("\n")[0] ?? ""}`,
          ]),
      ...(fingerprintMatches ? [] : [`the ${differing.join(", ")} differ`]),
      ...(mismatchedCounts.length === 0
        ? []
        : [`row counts differ in ${mismatchedCounts.join(", ")}`]),
    ];

    if (problems.length > 0) {
      throw new CliError(
        "check_failed",
        `The restored database differs from a full replay: ${problems.join("; ")}.`,
      );
    }

    return {
      key: found.manifest.key,
      schemaActions: plan.actions,
      fingerprintMatches,
      mismatchedCounts,
    };
  } finally {
    await stack.destroy();
  }
}

async function withRestored(
  url: string,
  delta: Awaited<ReturnType<typeof loadPgDelta>>,
): Promise<
  Awaited<ReturnType<typeof extractCatalog>> & {
    readonly signatures: ReadonlyMap<string, string>;
    readonly fingerprint: Fingerprint;
  }
> {
  const { client, close } = await connect(url);
  const pool = await openPgPool(url);

  try {
    return {
      ...(await extractCatalog(delta, pool)),
      signatures: await tableSignatures(client),
      fingerprint: await catalogFingerprint(client),
    };
  } finally {
    await Promise.allSettled([close(), pool.end()]);
  }
}
