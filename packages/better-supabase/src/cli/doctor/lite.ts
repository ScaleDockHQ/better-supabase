import type { Node } from "oxc-parser";

import type { LiteDriver } from "../../server/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { liteDriverOf } from "../introspect/lite.ts";
import { isSqliteLiteDriver } from "../lite.ts";
import {
  findLine,
  isCallOf,
  isMemberCall,
  isMethodCall,
  isModuleOf,
} from "./tree.ts";

/** `client.rpc(`, `$rpc(` or `rpcTransport(`. */
const isRpcCall = (node: Node): boolean =>
  isMethodCall(node, "rpc", "$rpc") || isCallOf(node, "rpcTransport", "$rpc");

const MISSING_FEATURES: readonly {
  readonly feature: string;
  readonly test: (node: Node) => boolean;
}[] = [
  {
    feature: "Realtime",
    test: (node) =>
      isModuleOf(node, "better-supabase/realtime") ||
      isMethodCall(node, "channel", "removeChannel"),
  },
  {
    feature: "Edge Functions",
    test: (node) => isMemberCall(node, "functions", "invoke"),
  },
];

/**
 * The `[db] driver` of a Supabase Lite project, or `undefined` for any other
 * project.
 */
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
    const line = findLine(file.text, isRpcCall);

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
    MISSING_FEATURES.flatMap(({ feature, test }) => {
      const line = findLine(file.text, test);

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
