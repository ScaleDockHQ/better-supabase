import { INTEGRATION_INFO } from "better-supabase/config";
import {
  integrationsForFramework,
  type Preset,
  type PresetAccess,
  type PresetConventions,
  type PresetFramework,
  type PresetPlatforms,
  PRESET_NAMES,
  presetField,
  PRESETS,
  PROVIDER_COMMENT,
} from "better-supabase/preset";
import {
  siAstro,
  siExpo,
  siHono,
  siModelcontextprotocol,
  siNextdotjs,
  siNuxt,
  siReact,
  siReactrouter,
  siSupabase,
  siSvelte,
  siTanstack,
  siVite,
} from "simple-icons";

import type { BrandMark } from "../components/site/brand-icons";
import type { PackageManager } from "./create";

import { orpcGlyph } from "../components/site/brand-icons";

/** A value shown in a control: its label and, where the label is not enough, a hint. */
export interface OptionInfo {
  readonly label: string;
  readonly hint?: string;
}

/** The preset select's value when the blocks match no named preset. */
export const CUSTOM_PRESET = {
  value: "custom",
  label: "Custom",
  description: "Your own selection, changed from a preset.",
} as const;

/** The preset select's items: every named preset, then Custom. */
export const PRESET_ITEMS: readonly { value: string; label: string }[] = [
  ...PRESET_NAMES.map((name) => ({ value: name, label: PRESETS[name].title })),
  { value: CUSTOM_PRESET.value, label: CUSTOM_PRESET.label },
];

export interface FrameworkInfo {
  readonly label: string;
  readonly mark: BrandMark;
}

const FRAMEWORK_LABELS = presetField("framework").labels;

function framework(name: PresetFramework, mark: BrandMark): FrameworkInfo {
  return { label: FRAMEWORK_LABELS[name].label, mark };
}

export const FRAMEWORKS = {
  next: framework("next", siNextdotjs),
  vite: framework("vite", siVite),
  "tanstack-start": framework("tanstack-start", siTanstack),
  expo: framework("expo", siExpo),
  sveltekit: framework("sveltekit", siSvelte),
  nuxt: framework("nuxt", siNuxt),
  hono: framework("hono", siHono),
  astro: framework("astro", siAstro),
  "react-router": framework("react-router", siReactrouter),
} satisfies Readonly<Record<PresetFramework, FrameworkInfo>>;

const PLATFORM_FIELD = presetField("platforms");

export const PLATFORMS: readonly PresetPlatforms[] = PLATFORM_FIELD.values;

export const PLATFORM_LABELS = {
  web: PLATFORM_FIELD.labels.web.label,
  native: PLATFORM_FIELD.labels.native.label,
  both: PLATFORM_FIELD.labels.both.label,
} satisfies Readonly<Record<PresetPlatforms, string>>;

/** The platforms a framework can build: Expo builds a native app, every other framework a web app. */
export function platformsFor(
  framework: PresetFramework,
): readonly PresetPlatforms[] {
  return framework === "expo" ? ["native", "both"] : ["web", "both"];
}

/** Why a platform is unavailable for a framework, or undefined when it is available. */
export function platformUnavailable(
  framework: PresetFramework,
  platforms: PresetPlatforms,
): string | undefined {
  if (platformsFor(framework).includes(platforms)) {
    return undefined;
  }

  return framework === "expo"
    ? "Expo builds a native app, so it needs Native or Web and native."
    : `A native-only app runs on Expo, not ${FRAMEWORKS[framework].label}.`;
}

/**
 * The preset on another framework, with the platforms moved to ones it can
 * build: web becomes native on Expo, and native becomes web elsewhere.
 */
export function withFramework(
  preset: Preset,
  framework: PresetFramework,
): Preset {
  if (platformsFor(framework).includes(preset.platforms)) {
    return { ...preset, framework };
  }

  return {
    ...preset,
    framework,
    platforms: framework === "expo" ? "native" : "web",
  };
}

/** The convention fields the Conventions group shows, in order. */
export const CONVENTION_KEYS = [
  "casing",
  "idType",
  "scope",
  "tenantName",
  "api",
] as const;

export type ConventionKey = (typeof CONVENTION_KEYS)[number];

export const FIELD_LABELS = {
  framework: presetField("framework").label,
  platforms: presetField("platforms").label,
  casing: presetField("casing").label,
  idType: presetField("idType").label,
  scope: presetField("scope").label,
  tenantName: presetField("tenantName").label,
  access: presetField("access").label,
  api: presetField("api").label,
  integrations: presetField("integrations").label,
} satisfies Readonly<Record<keyof PresetConventions, string>>;

export const CONVENTION_VALUES = {
  casing: presetField("casing").labels,
  idType: presetField("idType").labels,
  scope: presetField("scope").labels,
  tenantName: presetField("tenantName").labels,
  api: presetField("api").labels,
} satisfies {
  readonly [K in ConventionKey]: Readonly<
    Record<PresetConventions[K], OptionInfo>
  >;
};

/** A field's label for the conflicts list, or the key when it has none. */
export function fieldLabel(key: string): string {
  return (
    Object.entries(FIELD_LABELS).find(([name]) => name === key)?.[1] ?? key
  );
}

/** The authorization library the Create page can name next to `access: "provider"`. */
export const AUTHZ_LIBRARIES = ["permdock"] as const;

export type AuthzLibrary = (typeof AUTHZ_LIBRARIES)[number];

/** The `authz` parameter, or undefined when it is missing, unknown or the access model is not `provider`. */
export function initialAuthz(
  param: string | null,
  preset: Preset,
): AuthzLibrary | undefined {
  if (preset.access !== "provider") {
    return undefined;
  }

  return AUTHZ_LIBRARIES.find((each) => each === param);
}

export const AUTH_CHOICES = [
  "roles",
  "catalog",
  "permdock",
  "provider",
  "custom",
] as const;

export type AuthChoice = (typeof AUTH_CHOICES)[number];

export interface AuthChoiceInfo extends OptionInfo {
  readonly access: PresetAccess;
  readonly authz?: AuthzLibrary;
  readonly optional?: true;
}

const ACCESS_LABELS = presetField("access").labels;

export const AUTH_CHOICE_INFO = {
  roles: { ...ACCESS_LABELS.roles, access: "roles" },
  catalog: { ...ACCESS_LABELS.catalog, access: "catalog" },
  permdock: {
    label: "PermDock",
    hint: "Typed permissions from PermDock, plugged in as the authorization provider.",
    access: "provider",
    authz: "permdock",
    optional: true,
  },
  provider: { ...ACCESS_LABELS.provider, access: "provider" },
  custom: { ...ACCESS_LABELS.custom, access: "custom" },
} satisfies Readonly<Record<AuthChoice, AuthChoiceInfo>>;

/** The auth choice a preset and the `authz` parameter make. */
export function authChoiceOf(
  preset: Preset,
  authz: AuthzLibrary | undefined,
): AuthChoice {
  if (preset.access === "provider" && authz === "permdock") {
    return "permdock";
  }

  return preset.access;
}

/** A preset and the authorization library the Create page keeps next to it. */
export interface AuthSelection {
  readonly preset: Preset;
  readonly authz: AuthzLibrary | undefined;
}

/** The preset's access model and the `authz` value for an auth choice. */
export function withAuthChoice(
  preset: Preset,
  choice: AuthChoice,
): AuthSelection {
  const info: AuthChoiceInfo = AUTH_CHOICE_INFO[choice];

  return { preset: { ...preset, access: info.access }, authz: info.authz };
}

export type IntegrationName = Preset["integrations"][number];

export interface IntegrationInfo {
  readonly title: string;
  /** What `init` or `add` writes, one sentence. */
  readonly description: string;
  readonly files: readonly string[];
  readonly mark: BrandMark;
  readonly requires: readonly IntegrationName[];
}

export const INTEGRATIONS = {
  client: {
    ...INTEGRATION_INFO.client,
    files: ["lib/supabase/client.ts"],
    mark: siSupabase,
  },
  next: {
    ...INTEGRATION_INFO.next,
    files: ["lib/supabase/server.ts", "proxy.ts"],
    mark: siNextdotjs,
  },
  react: {
    ...INTEGRATION_INFO.react,
    files: ["providers.tsx", "lib/hooks.ts"],
    mark: siReact,
  },
  hono: { ...INTEGRATION_INFO.hono, files: ["server.ts"], mark: siHono },
  orpc: { ...INTEGRATION_INFO.orpc, files: ["router.ts"], mark: orpcGlyph },
  edge: {
    ...INTEGRATION_INFO.edge,
    files: ["supabase/functions/api"],
    mark: siSupabase,
  },
  expo: {
    ...INTEGRATION_INFO.expo,
    files: [
      "lib/supabase/expo.ts",
      "lib/supabase/client.native.ts",
      "app/+middleware.ts",
    ],
    mark: siExpo,
  },
  mcp: {
    ...INTEGRATION_INFO.mcp,
    files: ["supabase/functions/mcp"],
    mark: siModelcontextprotocol,
  },
} satisfies Readonly<Record<IntegrationName, IntegrationInfo>>;

/** The integrations in the order the panel lists them. */
export const INTEGRATION_ORDER = [
  "client",
  "next",
  "react",
  "hono",
  "orpc",
  "expo",
  "edge",
  "mcp",
] as const satisfies readonly IntegrationName[];

/** Why `init --preset` adds an integration on its own. */
export type ImpliedReason = "framework" | "required";

/**
 * The integrations `init --preset` adds for the framework whatever the
 * selection says (`integrationsForFramework`): the framework's own one,
 * when it has one, and what that one requires.
 */
export function impliedIntegrations(
  framework: PresetFramework,
): ReadonlyMap<IntegrationName, ImpliedReason> {
  return new Map(
    integrationsForFramework(framework).map((name, index) => [
      name,
      index === 0 ? "framework" : "required",
    ]),
  );
}

/** The note on a locked integration row. */
export function impliedNote(
  reason: ImpliedReason,
  framework: PresetFramework,
): string {
  const label = FRAMEWORKS[framework].label;

  return reason === "framework" ? `Added for ${label}` : `Needed by ${label}`;
}

const INSTALLS = {
  pnpm: "pnpm add",
  npm: "npm install",
  yarn: "yarn add",
  bun: "bun add",
} satisfies Readonly<Record<PackageManager, string>>;

const EXECS = {
  pnpm: "pnpm exec",
  npm: "npx",
  yarn: "yarn",
  bun: "bunx",
} satisfies Readonly<Record<PackageManager, string>>;

/** The PermDock version range that runs on better-supabase 0.9. */
export const PERMDOCK_PEER = ">=0.9.0 <0.10.0";

/** `permdock` added to the app, in the workspace package when there is one. */
export function permDockInstall(
  manager: PackageManager,
  pkg: string | undefined,
): string {
  const command = `${INSTALLS[manager]} permdock`;

  if (pkg === undefined) {
    return command;
  }

  switch (manager) {
    case "pnpm": {
      return `${command} --filter ./${pkg}`;
    }

    case "npm": {
      return `${command} --workspace ${pkg}`;
    }

    case "yarn":
    case "bun": {
      return `cd ${pkg} && ${command}`;
    }

    default: {
      const unknown: never = manager;

      return unknown;
    }
  }
}

const GENERATE = [
  "permdock rls generate --target sql --split helpers,seeds,indexes,policies,hook --seeds-out -",
  "supabase db schema declarative sync --no-apply -f permdock",
  "permdock rls generate --target sql --split helpers,seeds,indexes,policies,hook --seeds-out supabase/migrations/",
  "permdock supabase inspect --out",
  "permdock catalog --out permissions.catalog.json",
] as const;

/**
 * The PermDock commands that write the SQL helpers, the token hook, the
 * manifest and the catalog the provider reads, in order. `supabase` runs
 * as installed; `permdock` through the package manager.
 */
export function permDockGenerate(manager: PackageManager): readonly string[] {
  return GENERATE.map((command) =>
    command.startsWith("permdock ") ? `${EXECS[manager]} ${command}` : command,
  );
}

const PROVIDER_LINES = PROVIDER_COMMENT.join("\n");

const CONFIG_IMPORT = 'import { defineConfig } from "better-supabase/config";';

const PERMDOCK_HEADER = [
  'import { readFileSync } from "node:fs";',
  CONFIG_IMPORT,
  'import { authorizationProvider } from "permdock/better-supabase";',
  "",
  "const read = (file: string) =>",
  '  readFileSync(new URL(file, import.meta.url), "utf8");',
].join("\n");

const PERMDOCK_AUTHORIZATION = [
  "  authorization: authorizationProvider({",
  '    manifest: read("permdock.manifest.json"),',
  '    catalog: read("permissions.catalog.json"),',
  "  }),",
].join("\n");

type AuthzPrompt = (
  manager: PackageManager,
  pkg: string | undefined,
  configSource: string,
) => string;

const AUTHZ_PROMPTS = {
  permdock: (manager, pkg, configSource) =>
    [
      "## Authorization with PermDock",
      `PermDock 1.0 runs on better-supabase 0.9 (peer \`${PERMDOCK_PEER}\`). It plugs in as the authorization provider of the \`provider\` access model.`,
      [
        `1. Add the package: \`${permDockInstall(manager, pkg)}\`.`,
        "2. Generate the SQL helpers, the token hook, `permdock.manifest.json` and `permissions.catalog.json` from your PermDock policy, in this order:",
        "",
        "```bash",
        ...permDockGenerate(manager),
        "```",
        "",
        "3. Set `authorization` in the config to the PermDock provider, which reads the two files:",
        "",
        "```ts",
        withPermDock(configSource).trimEnd(),
        "```",
      ].join("\n"),
    ].join("\n\n"),
} as const satisfies Record<AuthzLibrary, AuthzPrompt>;

/**
 * The Markdown section of the `/create` AI instructions that sets up the
 * authorization library: add it, generate its files, then the config that
 * reads them (`configSource`, from `presetConfigSource`).
 */
export function authzPromptSection(
  authz: AuthzLibrary,
  manager: PackageManager,
  pkg: string | undefined,
  configSource: string,
): string {
  return AUTHZ_PROMPTS[authz](manager, pkg, configSource);
}

/**
 * The config `presetConfigSource` renders for `access: "provider"`, with
 * PermDock as the provider: the imports, a `read` helper for the two files
 * it generates, and `authorization` where the provider comment was.
 */
export function withPermDock(configSource: string): string {
  if (
    !configSource.includes(PROVIDER_LINES) ||
    !configSource.startsWith(CONFIG_IMPORT)
  ) {
    return configSource;
  }

  return configSource
    .replace(CONFIG_IMPORT, PERMDOCK_HEADER)
    .replace(PROVIDER_LINES, PERMDOCK_AUTHORIZATION);
}
