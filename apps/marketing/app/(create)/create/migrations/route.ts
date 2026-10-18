import { isPresetCode } from "better-supabase/preset";
import { cacheLife } from "next/cache";

import type { PresetMigrationFile } from "@/lib/create";

import { previewFiles } from "@/lib/preview-provider";

/**
 * The files `sql sync` writes for a config with only this preset. The SQL
 * renderers stay on the server: the browser resolves the preset itself and
 * fetches only the rendered files.
 */
// oxlint-disable-next-line typescript/require-await -- a "use cache" function must be async; rendering is synchronous
async function presetMigrations(
  code: string,
): Promise<readonly PresetMigrationFile[]> {
  "use cache";
  cacheLife("max");

  return previewFiles(code);
}

export async function GET(request: Request): Promise<Response> {
  const code = new URL(request.url).searchParams.get("preset") ?? "";

  if (!isPresetCode(code)) {
    return Response.json({ error: "preset must be a code" }, { status: 400 });
  }

  try {
    return Response.json({ files: await presetMigrations(code) });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 400 },
    );
  }
}
