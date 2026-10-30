import type { FhirTemporal } from "./shared.ts";
import type {
  FhirBundle,
  FhirBundleEntry,
  FhirBundleEntryRequest,
  FhirResource,
} from "./types.ts";

import { compact, fhirTime, nonEmpty } from "./shared.ts";

/** The bundle types `toFhirBundle` builds. */
export type FhirBundleKind =
  | "collection"
  | "searchset"
  | "transaction"
  | "batch";

export interface FhirBundleOptions {
  /** Default `collection`. */
  readonly type?: FhirBundleKind;
  readonly id?: string;
  /**
   * The server base, such as `https://example.com/fhir`. Entries with an id get
   * `fullUrl` `<baseUrl>/<type>/<id>`; without a base they get none.
   */
  readonly baseUrl?: string;
  readonly timestamp?: FhirTemporal;
}

function requestOf(resource: FhirResource): FhirBundleEntryRequest {
  return resource.id === undefined
    ? { method: "POST", url: resource.resourceType }
    : { method: "PUT", url: `${resource.resourceType}/${resource.id}` };
}

function entryOf<R extends FhirResource>(
  resource: R,
  kind: FhirBundleKind,
  baseUrl: string | undefined,
): FhirBundleEntry<R> {
  const fullUrl =
    baseUrl === undefined || resource.id === undefined
      ? undefined
      : `${baseUrl.replace(/\/+$/u, "")}/${resource.resourceType}/${resource.id}`;

  switch (kind) {
    case "collection": {
      return compact<FhirBundleEntry<R>>({ fullUrl, resource });
    }

    case "searchset": {
      return compact<FhirBundleEntry<R>>({
        fullUrl,
        resource,
        search: { mode: "match" },
      });
    }

    case "transaction":
    case "batch": {
      return compact<FhirBundleEntry<R>>({
        fullUrl,
        resource,
        request: requestOf(resource),
      });
    }

    default: {
      const never: never = kind;

      return never;
    }
  }
}

/**
 * Resources as a FHIR R4 `Bundle`: a `collection` by default, a `searchset`
 * with its total, or a `transaction` or `batch` that PUTs each resource with an
 * id and POSTs the rest.
 */
export function toFhirBundle<R extends FhirResource>(
  resources: readonly R[],
  options?: FhirBundleOptions,
): FhirBundle<R> {
  const kind = options?.type ?? "collection";

  return compact<FhirBundle<R>>({
    resourceType: "Bundle",
    id: options?.id,
    type: kind,
    timestamp: fhirTime(options?.timestamp),
    total: kind === "searchset" ? resources.length : undefined,
    entry: nonEmpty(
      resources.map((resource) => entryOf(resource, kind, options?.baseUrl)),
    ),
  });
}
