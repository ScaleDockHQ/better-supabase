import type { DbError } from "../core/errors.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { importOptionalPeer } from "../core/optional-peer.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

/** The error code `capabilitiesOf` returns when the catalog peer is missing. */
export const CHAT_CATALOG_MISSING = "CHAT_CATALOG_MISSING";

/** Whether an adapter supports one capability, with the catalog's qualifier. */
export interface ChatCapabilitySupport {
  readonly status: "yes" | "no" | "partial";
  /** A short qualifier such as `Native` or `Block Kit`. */
  readonly label?: string;
}

/** What `@chat-adapter/catalog` says about one adapter. */
export interface ChatAdapterCapabilities {
  readonly slug: string;
  readonly name: string;
  /** `platform` for a messaging platform, `state` for a state adapter. */
  readonly type: string;
  readonly group: string;
  readonly packageName: string;
  /** Every capability the catalog lists; a missing key means `no`. */
  readonly features: Readonly<Record<string, ChatCapabilitySupport>>;
}

interface CatalogModule {
  getCatalogEntry(slug: string): unknown;
}

const isCatalog = (value: unknown): value is CatalogModule =>
  isRecord(value) && typeof value["getCatalogEntry"] === "function";

const text = (value: unknown, fallback: string): string =>
  typeof value === "string" ? value : fallback;

function supportOf(value: unknown): ChatCapabilitySupport {
  if (typeof value === "string") {
    return { status: value === "yes" || value === "partial" ? value : "no" };
  }

  if (!isRecord(value)) {
    return { status: "no" };
  }

  const status = value["status"];
  const label = value["label"];

  return {
    status: status === "yes" || status === "partial" ? status : "no",
    ...(typeof label === "string" ? { label } : {}),
  };
}

const missing = (): DbError =>
  dbError(
    "unsupported",
    "capabilitiesOf needs the @chat-adapter/catalog package: pnpm add @chat-adapter/catalog",
    { code: CHAT_CATALOG_MISSING },
  );

/**
 * What the Chat SDK catalog lists for an adapter (`slack`, `whatsapp`, ...):
 * its package, type and capability matrix, so an app can pick a fallback before
 * it posts a card or a file. `@chat-adapter/catalog` is an optional peer loaded
 * on first use; without it the result is an `unsupported` error with the code
 * `CHAT_CATALOG_MISSING`. It never imports `chat/adapters`. An unknown name is
 * a `not_found` error. Pass `load` to supply the module yourself.
 */
export function capabilitiesOf(
  adapterName: string,
  options: { readonly load?: () => Promise<unknown> } = {},
): AsyncResult<ChatAdapterCapabilities> {
  return AsyncResult.from(async () => {
    const module = await (
      options.load ?? (() => importOptionalPeer("@chat-adapter/catalog"))
    )();

    if (!isCatalog(module)) {
      return err(missing());
    }

    const entry = module.getCatalogEntry(adapterName);

    if (!isRecord(entry)) {
      return err(
        dbError("not_found", `The Chat SDK catalog has no "${adapterName}"`),
      );
    }

    const features = isRecord(entry["features"]) ? entry["features"] : {};

    return ok({
      slug: text(entry["slug"], adapterName),
      name: text(entry["name"], adapterName),
      type: text(entry["type"], "platform"),
      group: text(entry["group"], "community"),
      packageName: text(entry["packageName"], ""),
      features: Object.fromEntries(
        Object.entries(features).map(([key, value]) => [key, supportOf(value)]),
      ),
    });
  });
}
