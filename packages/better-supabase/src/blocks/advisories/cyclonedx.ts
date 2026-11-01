import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { err, ok } from "../../core/result.ts";

/** A component of a CycloneDX BOM, flattened out of the component tree. */
export interface SbomComponent {
  /** The component's `bom-ref`, unique inside its BOM. */
  readonly bomRef: string | undefined;
  /** `library`, `application`, `framework`, `container` and so on. */
  readonly type: string;
  readonly name: string;
  readonly version: string | undefined;
  readonly group: string | undefined;
  /** The package URL, the key that vulnerability matching uses. */
  readonly purl: string | undefined;
  readonly cpe: string | undefined;
  readonly supplier: string | undefined;
  /** License ids, names and expressions. */
  readonly licenses: readonly string[];
  readonly hashes: readonly {
    readonly alg: string;
    readonly content: string;
  }[];
}

/** A CycloneDX document as the block stores it. */
export interface Sbom {
  /** `1.4` to `1.7`. */
  readonly specVersion: string;
  /** The `urn:uuid:` serial number, when the BOM has one. */
  readonly serialNumber: string | undefined;
  readonly components: readonly SbomComponent[];
}

/** The most components one import takes. */
export const MAX_SBOM_COMPONENTS = 20_000;

const SPEC_VERSION = /^1\.[4-7]$/u;

const SERIAL =
  /^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu;

function invalid(message: string, path: readonly PropertyKey[]): Result<never> {
  return err(dbError("validation", message, { issues: [{ message, path }] }));
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;

function licensesOf(value: unknown): readonly string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry): string[] => {
    if (!isRecord(entry)) {
      return [];
    }

    const expression = text(entry["expression"]);

    if (expression !== undefined) {
      return [expression];
    }

    const license = entry["license"];

    if (!isRecord(license)) {
      return [];
    }

    const found = text(license["id"]) ?? text(license["name"]);

    return found === undefined ? [] : [found];
  });
}

function hashesOf(
  value: unknown,
): readonly { readonly alg: string; readonly content: string }[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry) => {
    if (!isRecord(entry)) {
      return [];
    }

    const alg = text(entry["alg"]);
    const content = text(entry["content"]);

    return alg === undefined || content === undefined ? [] : [{ alg, content }];
  });
}

function componentOf(
  value: Record<string, unknown>,
): SbomComponent | undefined {
  const name = text(value["name"]);

  if (name === undefined) {
    return undefined;
  }

  const supplier = value["supplier"];

  return {
    bomRef: text(value["bom-ref"]),
    type: text(value["type"]) ?? "library",
    name,
    version: text(value["version"]),
    group: text(value["group"]),
    purl: text(value["purl"]),
    cpe: text(value["cpe"]),
    supplier: isRecord(supplier) ? text(supplier["name"]) : undefined,
    licenses: licensesOf(value["licenses"]),
    hashes: hashesOf(value["hashes"]),
  };
}

/** Collects `components` and their nested `components`, depth first. */
function collect(
  value: unknown,
  into: SbomComponent[],
  depth: number,
): boolean {
  if (!Array.isArray(value)) {
    return true;
  }

  if (depth > 32) {
    return false;
  }

  for (const entry of value) {
    if (!isRecord(entry)) {
      continue;
    }

    const component = componentOf(entry);

    if (component !== undefined) {
      into.push(component);
    }

    if (!collect(entry["components"], into, depth + 1)) {
      return false;
    }

    if (into.length > MAX_SBOM_COMPONENTS) {
      return true;
    }
  }

  return true;
}

/**
 * Reads a CycloneDX 1.4 to 1.7 JSON BOM (a string or a parsed value) into the
 * flat component list the block stores. Nested components are flattened,
 * components without a name are skipped, and a BOM with more than
 * `MAX_SBOM_COMPONENTS` components is refused. Every other part of the BOM
 * (services, dependencies, vulnerabilities) is ignored.
 */
export function parseCycloneDx(input: unknown): Result<Sbom> {
  let bom: unknown = input;

  if (typeof input === "string") {
    try {
      bom = JSON.parse(input);
    } catch {
      return invalid("the BOM is not valid JSON", []);
    }
  }

  if (!isRecord(bom) || bom["bomFormat"] !== "CycloneDX") {
    return invalid('bomFormat must be "CycloneDX"', ["bomFormat"]);
  }

  const specVersion = text(bom["specVersion"]);

  if (specVersion === undefined || !SPEC_VERSION.test(specVersion)) {
    return invalid("specVersion must be 1.4, 1.5, 1.6 or 1.7", ["specVersion"]);
  }

  const serial = text(bom["serialNumber"]);

  if (serial !== undefined && !SERIAL.test(serial)) {
    return invalid("serialNumber must be a urn:uuid", ["serialNumber"]);
  }

  const components: SbomComponent[] = [];

  if (!collect(bom["components"], components, 0)) {
    return invalid("components are nested more than 32 levels", ["components"]);
  }

  if (components.length > MAX_SBOM_COMPONENTS) {
    return invalid(
      `a BOM has at most ${String(MAX_SBOM_COMPONENTS)} components`,
      ["components"],
    );
  }

  return ok({ specVersion, serialNumber: serial, components });
}
