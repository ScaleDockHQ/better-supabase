/**
 * The frameworks better-supabase writes data hooks for, and how a third party
 * adds one.
 */

/**
 * `supported` bindings get the full test matrix; `community` ones a smoke test
 * (ADR 0094).
 */
export type FrameworkTier = "supported" | "community";

/** What a template reads about the app it writes into. */
export interface FrameworkTemplateContext {
  /** `src` or `.`. */
  readonly srcDir: string;
  /** The main generated module, relative to the project root. */
  readonly generated: string;
  /** Whether relative imports keep their `.ts` extension. */
  readonly tsExtensions: boolean;
  /**
   * The specifier of the framework's server adapter
   * (`better-supabase/<serverSubpath>`), or undefined when the binding has
   * none.
   */
  readonly serverImport: string | undefined;
}

export interface FrameworkTemplateFile {
  /** Relative to the project root. */
  readonly path: string;
  readonly contents: string;
}

/** The contract version of a framework binding. */
export const FRAMEWORK_API_VERSION = 1;

/**
 * A framework binding at `apiVersion: 1`: plain data, so `gen`, `init` and the
 * capability registry derive everything about the framework from one place.
 */
export interface FrameworkBinding {
  readonly apiVersion: 1;
  /** The value of `gen.hooks`: `react`, `vue`, `qwik`. */
  readonly name: string;
  readonly tier: FrameworkTier;
  /** Package names that identify the framework in an app's `package.json`. */
  readonly detect: readonly string[];
  /**
   * `integrations` entries that select this framework when `gen.hooks` is unset
   * (`next` selects `react`).
   */
  readonly integrations?: readonly string[];
  /**
   * The runtime subpath that exports `defineListHook` and `defineOneHook`:
   * `better-supabase/<hooksSubpath>`. Defaults to `name`.
   */
  readonly hooksSubpath?: string;
  /**
   * A full module specifier that exports them, for a framework whose hooks live
   * in another package. Takes precedence over `hooksSubpath`.
   */
  readonly hooksModule?: string;
  /** A directive the first line of `hooks.ts` carries (`"use client";`). */
  readonly hooksDirective?: string;
  /** The runtime subpath of the framework's server adapter, when it has one. */
  readonly serverSubpath?: string;
  /** Files `init` writes when it detects the framework. */
  readonly templates?: (
    context: FrameworkTemplateContext,
  ) => readonly FrameworkTemplateFile[];
}

/** What `defineFramework` takes: a binding without its `apiVersion`. */
export type FrameworkDefinition = Omit<FrameworkBinding, "apiVersion">;

const NAME = /^[a-z][a-z0-9-]*$/;

/** What is wrong with a binding, or `undefined`. */
export function frameworkProblem(binding: unknown): string | undefined {
  if (typeof binding !== "object" || binding === null) {
    return "a framework is an object: { apiVersion: 1, name, tier, detect }";
  }

  const name =
    "name" in binding && typeof binding.name === "string"
      ? binding.name
      : undefined;

  if (name === undefined || !NAME.test(name)) {
    return "a framework needs a `name` in lowercase letters, digits and dashes";
  }

  const api = "apiVersion" in binding ? binding.apiVersion : undefined;

  if (api !== FRAMEWORK_API_VERSION) {
    return `framework "${name}" targets framework API ${api === undefined ? "none" : String(api)}; this better-supabase runs ${FRAMEWORK_API_VERSION}. Build it with defineFramework.`;
  }

  if (
    !("tier" in binding) ||
    (binding.tier !== "supported" && binding.tier !== "community")
  ) {
    return `framework "${name}" needs a \`tier\`: "supported" or "community"`;
  }

  if (
    !("detect" in binding) ||
    !Array.isArray(binding.detect) ||
    binding.detect.length === 0
  ) {
    return `framework "${name}" needs \`detect\`: the package names that identify it`;
  }

  return undefined;
}

/** Declares a binding; register it with `gen.frameworks`. */
export function defineFramework(
  definition: FrameworkDefinition,
): FrameworkBinding {
  const binding: FrameworkBinding = {
    apiVersion: FRAMEWORK_API_VERSION,
    ...definition,
  };

  const problem = frameworkProblem(binding);

  if (problem !== undefined) {
    throw new TypeError(problem);
  }

  return binding;
}

const meta = (
  name: string,
  detect: string,
  hooksSubpath: string,
): FrameworkBinding =>
  defineFramework({
    name,
    tier: "supported",
    detect: [detect],
    hooksSubpath,
    serverSubpath: name,
    ...(hooksSubpath === "react" ? { hooksDirective: '"use client";' } : {}),
  });

/**
 * The frameworks `gen.hooks` supports without registration. A meta-framework
 * comes before the library it builds on, since `detect` returns the first match
 * (ADR 0582).
 */
export const BUILT_IN_FRAMEWORKS: readonly FrameworkBinding[] = [
  meta("sveltekit", "@sveltejs/kit", "svelte"),
  meta("tanstack-start", "@tanstack/react-start", "react"),
  meta("react-router", "@react-router/dev", "react"),
  defineFramework({
    name: "react",
    tier: "supported",
    detect: ["react"],
    integrations: ["next", "react", "expo"],
    hooksDirective: '"use client";',
  }),
  defineFramework({ name: "svelte", tier: "supported", detect: ["svelte"] }),
  defineFramework({ name: "vue", tier: "community", detect: ["vue"] }),
  defineFramework({ name: "solid", tier: "community", detect: ["solid-js"] }),
];

/** The registered bindings, by name. */
export interface FrameworkRegistry {
  readonly bindings: readonly FrameworkBinding[];
  readonly names: readonly string[];
  get(name: string): FrameworkBinding | undefined;
  /** The first binding whose package is in `dependencies`. */
  detect(
    dependencies: Readonly<Record<string, unknown>>,
  ): FrameworkBinding | undefined;
  /** The binding an `integrations` list selects when `gen.hooks` is unset. */
  forIntegrations(
    integrations: readonly string[],
  ): FrameworkBinding | undefined;
}

/** The built-in bindings plus `extra`; a duplicate name is an error. */
export function frameworkRegistry(
  extra: readonly FrameworkBinding[] = [],
): FrameworkRegistry {
  const bindings = [...BUILT_IN_FRAMEWORKS];

  for (const binding of extra) {
    // A resolved config lists the built-in bindings next to its own.
    if (bindings.includes(binding)) {
      continue;
    }

    const problem = frameworkProblem(binding);

    if (problem !== undefined) {
      throw new TypeError(problem);
    }

    if (bindings.some((known) => known.name === binding.name)) {
      throw new TypeError(`framework "${binding.name}" is already registered`);
    }

    bindings.push(binding);
  }

  return {
    bindings,
    names: bindings.map((binding) => binding.name),
    get: (name) => bindings.find((binding) => binding.name === name),
    detect: (dependencies) =>
      bindings.find((binding) =>
        binding.detect.some((name) => Object.hasOwn(dependencies, name)),
      ),
    forIntegrations: (integrations) =>
      bindings.find((binding) =>
        (binding.integrations ?? []).some((name) =>
          integrations.includes(name),
        ),
      ),
  };
}

/** The subpath `hooks.ts` imports `defineListHook` from. */
export const hooksSubpathOf = (binding: FrameworkBinding): string =>
  binding.hooksSubpath ?? binding.name;

/** The specifier of a binding's server adapter, or undefined. */
export const serverImportOf = (
  binding: FrameworkBinding,
): string | undefined =>
  binding.serverSubpath === undefined
    ? undefined
    : `better-supabase/${binding.serverSubpath}`;

/** The files `init` writes for a binding. */
export const frameworkFiles = (
  binding: FrameworkBinding,
  context: Omit<FrameworkTemplateContext, "serverImport">,
): readonly FrameworkTemplateFile[] =>
  binding.templates?.({ ...context, serverImport: serverImportOf(binding) }) ??
  [];
