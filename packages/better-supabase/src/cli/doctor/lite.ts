import type { LiteDriver } from "../../server/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { liteDriverOf } from "../introspect/lite.ts";
import { isSqliteLiteDriver } from "../lite.ts";
import { lineOf } from "./shared.ts";

const RPC_CALL = /(?:\.|\$)rpc\s*\(|\brpcTransport\s*\(/;

const MISSING_FEATURES: readonly {
  readonly feature: string;
  readonly pattern: RegExp;
}[] = [
  {
    feature: "Realtime",
    pattern:
      /from\s+["']better-supabase\/realtime["']|\.channel\s*\(|\.removeChannel\s*\(/,
  },
  {
    feature: "Edge Functions",
    pattern: /\.functions\.invoke\s*\(|\bfunctions\(\)\.invoke\s*\(/,
  },
];

/** The `[db] driver` of a Supabase Lite project, or `undefined` for any other project. */
function liteDriver(context: DoctorContext): LiteDriver | undefined {
  try {
    return liteDriverOf(context.configToml);
  } catch {
    return;
  }
}

function rpcOnSqlite(context: DoctorContext): FindingInput[] {
  const driver = liteDriver(context);

  if (driver === undefined || !isSqliteLiteDriver(driver)) {
    return [];
  }

  return context.sources.flatMap((file) => {
    const line = lineOf(file.text, RPC_CALL);

    if (line === undefined) {
      return [];
    }

    return [
      {
        message: `${file.path} calls a Postgres function, but Supabase Lite's ${driver} driver has no rpc(), so the call returns an unsupported error. Switch [db] driver to "pglite" or "postgres" in supabase/config.toml, or replace the function with table queries.`,
        target: `${file.path}:rpc`,
        location: { file: file.path, line },
      },
    ];
  });
}

function missingLiteFeature(context: DoctorContext): FindingInput[] {
  if (liteDriver(context) === undefined) {
    return [];
  }

  return context.sources.flatMap((file) =>
    MISSING_FEATURES.flatMap(({ feature, pattern }) => {
      const line = lineOf(file.text, pattern);

      if (line === undefined) {
        return [];
      }

      return [
        {
          message: `${file.path} uses ${feature}, which Supabase Lite does not implement on any driver. Run the full Supabase stack for this feature, or move the project off Lite with \`supabase lite upgrade\`.`,
          target: `${file.path}:${feature}`,
          location: { file: file.path, line },
        },
      ];
    }),
  );
}

export const LITE_RULES: readonly Rule[] = [
  {
    code: "BS328",
    severity: "warning",
    title: "rpc() on a Supabase Lite SQLite driver",
    description:
      "`[db] driver` in `config.toml` is `sqlite-postgres` or `sqlite`, which have no `rpc()`, but the app calls a Postgres function. Those calls return an `unsupported` error.",
    check: rpcOnSqlite,
  },
  {
    code: "BS329",
    severity: "warning",
    title: "Feature Supabase Lite does not implement",
    description:
      "`config.toml` sets `[db] driver`, so the project runs on Supabase Lite, but the app uses Realtime or Edge Functions, which Lite does not implement.",
    check: missingLiteFeature,
  },
];
