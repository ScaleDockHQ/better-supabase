/**
 * The official JSON Schemas `spec validate` checks documents against, vendored
 * unmodified under `schemas/` (sources and SHA-256 in
 * `tests/standards/schemas/SOURCES.md`). Each loads on first use, so a command
 * that validates one format never parses the others.
 */

export type SchemaDialect = "draft-04" | "draft-07" | "2020-12";

export interface OfficialSchema {
  /** The schema's `$id`, also the key it is compiled under. */
  readonly id: string;
  readonly dialect: SchemaDialect;
  readonly load: () => Promise<unknown>;
}

const json = (module: { readonly default: unknown }): unknown => module.default;

/** Keyed by `<format>@<version>`, the format's own version names. */
export const OFFICIAL_SCHEMAS: ReadonlyMap<string, OfficialSchema> = new Map([
  [
    "openapi@3.0",
    {
      id: "https://spec.openapis.org/oas/3.0/schema/2024-10-18",
      dialect: "draft-04",
      load: () =>
        import("./schemas/openapi-3.0.json", { with: { type: "json" } }).then(
          json,
        ),
    },
  ],
  [
    "openapi@3.1",
    {
      id: "https://spec.openapis.org/oas/3.1/schema/2026-08-03",
      dialect: "2020-12",
      load: () =>
        import("./schemas/openapi-3.1.json", { with: { type: "json" } }).then(
          json,
        ),
    },
  ],
  [
    "openapi@3.2",
    {
      id: "https://spec.openapis.org/oas/3.2/schema/2026-08-30",
      dialect: "2020-12",
      load: () =>
        import("./schemas/openapi-3.2.json", { with: { type: "json" } }).then(
          json,
        ),
    },
  ],
  [
    "asyncapi@3.0",
    {
      id: "http://asyncapi.com/definitions/3.0.0/asyncapi.json",
      dialect: "draft-07",
      load: () =>
        import("./schemas/asyncapi-3.0.0.json", {
          with: { type: "json" },
        }).then(json),
    },
  ],
  [
    "asyncapi@3.1",
    {
      id: "http://asyncapi.com/definitions/3.1.0/asyncapi.json",
      dialect: "draft-07",
      load: () =>
        import("./schemas/asyncapi-3.1.0.json", {
          with: { type: "json" },
        }).then(json),
    },
  ],
  [
    "arazzo@1.0",
    {
      id: "https://spec.openapis.org/arazzo/1.0/schema/2025-10-15",
      dialect: "2020-12",
      load: () =>
        import("./schemas/arazzo-1.0.json", { with: { type: "json" } }).then(
          json,
        ),
    },
  ],
  [
    "arazzo@1.1",
    {
      id: "https://spec.openapis.org/arazzo/1.1/schema/2026-04-15",
      dialect: "2020-12",
      load: () =>
        import("./schemas/arazzo-1.1.json", { with: { type: "json" } }).then(
          json,
        ),
    },
  ],
]);

/** The official schema for a format version, if one is vendored. */
export function officialSchema(
  format: string,
  version: string,
): OfficialSchema | undefined {
  return OFFICIAL_SCHEMAS.get(`${format}@${version}`);
}
