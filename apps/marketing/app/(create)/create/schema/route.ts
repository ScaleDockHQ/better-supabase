import {
  previewFiles,
  parseSchema,
  type SchemaData,
  tenantColumnOf,
  schemaData,
} from "better-supabase/create";
import { isPresetCode, presetOf } from "better-supabase/preset";
import { cacheLife } from "next/cache";

/**
 * The tables the preset's modules create, read from the same SQL
 * `/create/migrations` returns, with the soft references, manifests and
 * extra-column tables the diagram on `/create` draws.
 */
// oxlint-disable-next-line typescript/require-await -- a "use cache" function must be async; parsing is synchronous
async function presetSchema(code: string): Promise<SchemaData> {
  "use cache";
  cacheLife("max");

  const preset = presetOf(code);

  return schemaData(
    parseSchema(previewFiles(code), { tenantColumn: tenantColumnOf(preset) }),
    preset.tenantName,
  );
}

export async function GET(request: Request): Promise<Response> {
  const code = new URL(request.url).searchParams.get("preset") ?? "";

  if (!isPresetCode(code)) {
    return Response.json({ error: "preset must be a code" }, { status: 400 });
  }

  try {
    return Response.json(await presetSchema(code));
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 400 },
    );
  }
}
