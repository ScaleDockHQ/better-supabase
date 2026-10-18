import {
  decodeDesign,
  encodePreset,
  isDesignCode,
  isPresetCode,
  isPresetName,
  namedPreset,
  presetOf,
  resolvePreset,
} from "better-supabase/preset";
import { cacheLife } from "next/cache";

import { DEFAULT_PRESET, PACKAGE_MANAGERS, packageDir } from "@/lib/create";
import { AUTHZ_LIBRARIES, initialAuthz } from "@/lib/create-options";
import { presetPrompt } from "@/lib/create-prompt";
import { markdownHeaders } from "@/lib/markdown";
import { site } from "@/lib/site";

/**
 * The AI instructions `/create` copies, for an agent to fetch:
 * `?preset=<code or name>&design=<code>&ui=1&package=<dir>&authz=<library>&manager=<pm>`.
 * Every parameter is optional; the preset defaults to the one `/create` opens on.
 */
async function promptMarkdown(
  code: string,
  designCode: string,
  ui: boolean,
  pkg: string | undefined,
  authz: string | null,
  manager: (typeof PACKAGE_MANAGERS)[number],
): Promise<string> {
  "use cache";
  cacheLife("max");

  const preset = presetOf(code);
  const design = designCode === "" ? {} : await decodeDesign(designCode);

  return presetPrompt({
    resolved: resolvePreset(preset),
    design,
    designCode,
    ui,
    manager,
    pkg,
    authz: initialAuthz(authz, preset),
    siteUrl: site.url,
  });
}

function presetCode(param: string | null): string | undefined {
  if (param === null || param === "") {
    return encodePreset(namedPreset(DEFAULT_PRESET));
  }

  if (isPresetName(param)) {
    return encodePreset(namedPreset(param));
  }

  return isPresetCode(param) ? param : undefined;
}

const badRequest = (error: string): Response =>
  Response.json({ error }, { status: 400 });

export async function GET(request: Request): Promise<Response> {
  const params = new URL(request.url).searchParams;
  const code = presetCode(params.get("preset"));

  if (code === undefined) {
    return badRequest("preset must be a code or a preset name");
  }

  const designCode = params.get("design") ?? "";

  if (designCode !== "" && !isDesignCode(designCode)) {
    return badRequest("design must be a design code from /create");
  }

  const ui = params.get("ui");

  if (ui !== null && ui !== "0" && ui !== "1") {
    return badRequest("ui must be 0 or 1");
  }

  const pkgParam = params.get("package");
  const pkg = packageDir(pkgParam);

  if (pkgParam !== null && pkg === undefined) {
    return badRequest("package must be a directory inside the repository");
  }

  const authz = params.get("authz");

  if (authz !== null && !AUTHZ_LIBRARIES.some((each) => each === authz)) {
    return badRequest(`authz must be one of ${AUTHZ_LIBRARIES.join(", ")}`);
  }

  const managerParam = params.get("manager") ?? "pnpm";
  const manager = PACKAGE_MANAGERS.find((each) => each === managerParam);

  if (manager === undefined) {
    return badRequest(`manager must be one of ${PACKAGE_MANAGERS.join(", ")}`);
  }

  try {
    return new Response(
      await promptMarkdown(code, designCode, ui === "1", pkg, authz, manager),
      { headers: markdownHeaders },
    );
  } catch (error) {
    return badRequest(error instanceof Error ? error.message : String(error));
  }
}
