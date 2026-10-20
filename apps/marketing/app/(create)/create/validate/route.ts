import type { DesignValidation } from "better-supabase/create/lite";

import { createPgliteConnection } from "@supabase/lite/pglite";
import { previewFiles } from "better-supabase/create";
import { validateDesign } from "better-supabase/create/lite";
import {
  decodeDesign,
  isDesignCode,
  isPresetCode,
} from "better-supabase/preset";
import { cacheLife } from "next/cache";

type LiteRuntime = NonNullable<
  NonNullable<Parameters<typeof validateDesign>[1]>["runtime"]
>;

function unused(): never {
  throw new Error("Validation only runs on PGlite.");
}

/**
 * The static import keeps `@supabase/lite/pglite` in the traced function;
 * the library's own loader imports it by a variable specifier that tracing
 * can't follow. Validation only opens a PGlite connection.
 */
const runtime: LiteRuntime = {
  App: class {
    constructor() {
      unused();
    }

    init = unused;
    fetch = unused;
  },
  createPgliteConnection,
  createSqliteConnection: unused,
};

/** The files `/create/migrations` renders, applied to an in-memory Postgres. */
async function validatePreset(
  code: string,
  designCode: string,
): Promise<DesignValidation> {
  "use cache";
  cacheLife("max");

  return validateDesign(previewFiles(code, await decodeDesign(designCode)), {
    runtime,
  });
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
    return Response.json(await validatePreset(code, designCode));
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : String(error) },
      { status: 500 },
    );
  }
}
