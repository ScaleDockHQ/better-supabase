import {
  type Preset,
  type PresetAccess,
  type PresetConventions,
  type PresetFramework,
  type PresetPlatforms,
  PRESET_NAMES,
  PRESETS,
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

export const FRAMEWORKS = {
  next: { label: "Next.js", mark: siNextdotjs },
  vite: { label: "Vite", mark: siVite },
  "tanstack-start": { label: "TanStack Start", mark: siTanstack },
  expo: { label: "Expo", mark: siExpo },
  sveltekit: { label: "SvelteKit", mark: siSvelte },
  nuxt: { label: "Nuxt", mark: siNuxt },
  hono: { label: "Hono", mark: siHono },
  astro: { label: "Astro", mark: siAstro },
  "react-router": { label: "React Router", mark: siReactrouter },
} satisfies Readonly<Record<PresetFramework, FrameworkInfo>>;

export const PLATFORMS = ["web", "native", "both"] as const;

export const PLATFORM_LABELS = {
  web: "Web",
  native: "Native",
  both: "Web and native",
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
  framework: "Framework",
  platforms: "Platforms",
  casing: "Casing",
  idType: "ID type",
  scope: "Row ownership",
  tenantName: "Tenant name",
  access: "Auth and permissions",
  api: "API schema",
  integrations: "Integrations",
} satisfies Readonly<Record<keyof PresetConventions, string>>;

export const CONVENTION_VALUES = {
  casing: {
    snake: { label: "snake_case", hint: "Rows keep the database names." },
    camel: {
      label: "camelCase",
      hint: "Rows are renamed inside the PostgREST query.",
    },
  },
  idType: {
    uuid: { label: "UUID" },
    text: { label: "Text" },
    bigint: { label: "Bigint" },
    integer: { label: "Integer" },
  },
  scope: {
    tenant: {
      label: "Per tenant",
      hint: "Rows belong to a tenant, checked through access.",
    },
    user: { label: "Per user", hint: "Rows belong to the signed-in user." },
    none: {
      label: "Shared",
      hint: "One shared space for every signed-in user.",
    },
  },
  tenantName: {
    organization: { label: "Organization" },
    workspace: { label: "Workspace" },
    team: { label: "Team" },
  },
  api: {
    none: {
      label: "Module schema only",
      hint: "The Data API reaches no module tables.",
    },
    api: {
      label: "Data API schema (api)",
      hint: "Security invoker wrappers in an api schema, so the Data API reaches them without exposing the module schema.",
    },
  },
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

export const AUTH_CHOICE_INFO = {
  roles: {
    label: "Built-in roles",
    hint: "Owner, admin, member and viewer, mapped to permission keys in the config.",
    access: "roles",
  },
  catalog: {
    label: "Permissions tables",
    hint: "Role, permission and override tables in the database.",
    access: "catalog",
  },
  permdock: {
    label: "PermDock",
    hint: "Typed permissions from PermDock, plugged in as the authorization provider.",
    access: "provider",
    authz: "permdock",
    optional: true,
  },
  provider: {
    label: "Your own provider",
    hint: "Any library that implements AuthorizationProvider.",
    access: "provider",
  },
  custom: {
    label: "Custom SQL",
    hint: "Your own SQL expressions.",
    access: "custom",
  },
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
    title: "Browser client",
    description:
      "A browser client with cookie sessions shared with the server.",
    files: ["lib/supabase/client.ts"],
    mark: siSupabase,
    requires: [],
  },
  next: {
    title: "Next.js",
    description:
      "The proxy, and helpers for Server Components, route handlers and actions.",
    files: ["lib/supabase/server.ts", "proxy.ts"],
    mark: siNextdotjs,
    requires: ["client"],
  },
  react: {
    title: "React",
    description: "A React provider and typed TanStack Query hooks.",
    files: ["providers.tsx", "lib/hooks.ts"],
    mark: siReact,
    requires: ["client"],
  },
  hono: {
    title: "Hono",
    description: "Hono middleware, handlers and REST resources.",
    files: ["server.ts"],
    mark: siHono,
    requires: [],
  },
  orpc: {
    title: "oRPC",
    description: "oRPC middleware with a typed context and ORPCError mapping.",
    files: ["router.ts"],
    mark: orpcGlyph,
    requires: [],
  },
  edge: {
    title: "Edge Function",
    description: "A Supabase Edge Function with CORS and Problem Details.",
    files: ["supabase/functions/api"],
    mark: siSupabase,
    requires: [],
  },
  expo: {
    title: "Expo",
    description:
      "Expo Router server loaders, API routes and middleware, and a native client.",
    files: [
      "lib/supabase/expo.ts",
      "lib/supabase/client.native.ts",
      "app/+middleware.ts",
    ],
    mark: siExpo,
    requires: ["client"],
  },
  mcp: {
    title: "MCP server",
    description: "An MCP server over Streamable HTTP, as an Edge Function.",
    files: ["supabase/functions/mcp"],
    mark: siModelcontextprotocol,
    requires: [],
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

function isIntegrationName(name: string): name is IntegrationName {
  return Object.hasOwn(INTEGRATIONS, name);
}

/**
 * The integrations `init --preset` adds for the framework whatever the
 * selection says: the framework's own one, when it has one, and what that
 * one requires.
 */
export function impliedIntegrations(
  framework: PresetFramework,
): ReadonlyMap<IntegrationName, ImpliedReason> {
  const implied = new Map<IntegrationName, ImpliedReason>();

  if (isIntegrationName(framework)) {
    implied.set(framework, "framework");

    for (const each of INTEGRATIONS[framework].requires) {
      implied.set(each, "required");
    }
  }

  return implied;
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

const PROVIDER_COMMENT = [
  "  // The provider access model reads roles from your authorization",
  "  // library: set `authorization` to its adapter.",
].join("\n");

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

/**
 * The config `presetConfigSource` renders for `access: "provider"`, with
 * PermDock as the provider: the imports, a `read` helper for the two files
 * it generates, and `authorization` where the provider comment was.
 */
export function withPermDock(configSource: string): string {
  if (
    !configSource.includes(PROVIDER_COMMENT) ||
    !configSource.startsWith(CONFIG_IMPORT)
  ) {
    return configSource;
  }

  return configSource
    .replace(CONFIG_IMPORT, PERMDOCK_HEADER)
    .replace(PROVIDER_COMMENT, PERMDOCK_AUTHORIZATION);
}
