import {
  decodeDesign,
  isDesignCode,
  isPresetCode,
} from "better-supabase/preset";
import { cacheLife } from "next/cache";

import type { PresetMigrationFile } from "@/lib/create";

import { previewFiles } from "@/lib/preview-provider";

/**
 * The files `sql sync` writes for a config with only this preset and the
 * `/create` design in `designCode`. The SQL renderers stay on the server:
 * the browser resolves the preset itself and fetches only the rendered
 * files.
 */
async function presetMigrations(
  code: string,
  designCode: string,
): Promise<readonly PresetMigrationFile[]> {
  "use cache";
  cacheLife("max");

  return previewFiles(code, await decodeDesign(designCode));
}

export async function GET(request: Request): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const code = params.get("preset") ?? "";
  const designCode = params.get("design") ?? "";

  if (!isPresetCode(code)) {
    return Response.json({ error: "preset must be a code" }, { status: 400 });
  }

  if (designCode !== "" && !isDesignCode(designCode)) {
    return Response.json({ error: "design must be a code" }, { status: 400 });
  }

  try {
    return Response.json({ files: await presetMigrations(code, designCode) });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 400 },
    );
  }
}
