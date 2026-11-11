/**
 * Every default `resolveConfig` fills in. Other modules (the SQL module
 * registry, the CLI) read their fallbacks from here instead of repeating the
 * literals.
 */
export const CONFIG_DEFAULTS: {
  readonly output: string;
  readonly schemas: readonly string[];
  readonly casing: "snake";
  readonly postgrestVersion: string;
  readonly codecs: {
    readonly timestamptz: "string";
    readonly int8: "number";
    readonly numeric: "number";
  };
  readonly sql: {
    readonly dir: string;
    readonly prefix: string;
    readonly testsDir: string;
  };
  readonly seed: {
    readonly entry: string;
    readonly file: string;
    readonly perTenant: string;
    readonly defaults: { readonly onCreate: boolean; readonly locale: string };
    readonly sample: {
      readonly size: "s" | "m" | "l";
      readonly seed: number;
      readonly file: string;
    };
  };
  readonly specs: {
    readonly entry: string;
    readonly file: string;
    readonly failOn: "error";
  };
  readonly doctor: {
    readonly format: "text";
    readonly sources: readonly string[];
    readonly policyHelperLimit: number;
    readonly parallelReads: number;
  };
  readonly gen: { readonly watchInterval: number };
  readonly env: { readonly file: string };
} = {
  output: "src/lib/supabase/generated.ts",
  schemas: ["public"],
  casing: "snake",
  postgrestVersion: "13",
  codecs: { timestamptz: "string", int8: "number", numeric: "number" },
  sql: {
    dir: "supabase/schemas",
    prefix: "900_better_supabase",
    testsDir: "supabase/tests",
  },
  seed: {
    entry: "supabase/seed.ts",
    file: "supabase/seeds/000_better_supabase.sql",
    perTenant: "supabase/seed.tenant.ts",
    defaults: { onCreate: true, locale: "en" },
    sample: { size: "m", seed: 1, file: "supabase/seeds/900_sample.sql" },
  },
  specs: { entry: "src/lib/openapi.ts", file: "openapi.json", failOn: "error" },
  doctor: {
    format: "text",
    sources: ["src/**/*.{ts,tsx}"],
    policyHelperLimit: 5,
    parallelReads: 3,
  },
  gen: { watchInterval: 2000 },
  env: { file: ".env.local" },
};
