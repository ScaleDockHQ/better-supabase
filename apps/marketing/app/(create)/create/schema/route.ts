import { resolveConfig } from "better-supabase/config";
import { isPresetCode, presetOf } from "better-supabase/preset";
import { moduleLayout, renderModules } from "better-supabase/sql";
import { cacheLife } from "next/cache";

import { parseSchema, type SchemaTable, tenantColumnOf } from "@/lib/schema";

/**
 * The tables the preset's modules create, read from the same SQL
 * `/create/migrations` returns, for the diagram on `/create`.
 */
// oxlint-disable-next-line typescript/require-await -- a "use cache" function must be async; parsing is synchronous
async function presetSchema(code: string): Promise<readonly SchemaTable[]> {
  "use cache";
  cacheLife("max");
  const config = resolveConfig({ preset: code }, "/");

  return parseSchema(renderModules(config.blockNames, moduleLayout(config)), {
    tenantColumn: tenantColumnOf(presetOf(code)),
  });
}

export async function GET(request: Request): Promise<Response> {
  const code = new URL(request.url).searchParams.get("preset") ?? "";

  if (!isPresetCode(code)) {
    return Response.json({ error: "preset must be a code" }, { status: 400 });
  }

  try {
    return Response.json({ tables: await presetSchema(code) });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 400 },
    );
  }
}
