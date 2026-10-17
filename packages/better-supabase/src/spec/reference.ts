import { isPlainObject } from "../core/clone.ts";
import { methodNotAllowed } from "../core/problem.ts";

/** A plain object this module may change: callers pass a fresh copy. */
const isRecord = (value: unknown): value is Record<string, unknown> =>
  isPlainObject(value);

/** A docs UI that renders an OpenAPI document. */
export type SpecUi = "scalar" | "swagger" | "redoc" | "elements" | "rapidoc";

export const SPEC_UIS: readonly SpecUi[] = [
  "scalar",
  "swagger",
  "redoc",
  "elements",
  "rapidoc",
];

/** The package and version each UI loads from the CDN by default. */
export const SPEC_UI_PACKAGES: Readonly<
  Record<SpecUi, { readonly name: string; readonly version: string }>
> = {
  scalar: { name: "@scalar/api-reference", version: "1.73.1" },
  swagger: { name: "swagger-ui-dist", version: "5.33.1" },
  redoc: { name: "redoc", version: "2.5.4" },
  elements: { name: "@stoplight/elements", version: "9.0.28" },
  rapidoc: { name: "rapidoc", version: "10.1.0" },
};

const DEFAULT_CDN = "https://cdn.jsdelivr.net/npm";

interface PinnedFile {
  readonly path: string;
  /** Subresource Integrity of the file at the pinned version. */
  readonly integrity: string;
}

interface PinnedUi {
  readonly scripts: readonly PinnedFile[];
  readonly styles: readonly PinnedFile[];
}

const PINNED: Readonly<Record<SpecUi, PinnedUi>> = {
  scalar: {
    scripts: [
      {
        path: "dist/browser/standalone.js",
        integrity:
          "sha384-kYDGzV91Jnn3TbHINV3nt54riK2uMJDfN5Al8dAkz4FssELTBWbD8rgw32sTKfOi",
      },
    ],
    styles: [],
  },
  swagger: {
    scripts: [
      {
        path: "swagger-ui-bundle.js",
        integrity:
          "sha384-ZPehFMQommnnuaZ4rpxgkgTT2DKFVp4hZC/7pLit+9Lek9T1YGSo23eHFbvNkXkw",
      },
    ],
    styles: [
      {
        path: "swagger-ui.css",
        integrity:
          "sha384-Ov4/wv3j2bmct8cDc5X4ngJZohVPzEmc6uDPH8WeljUxO5vtoykvMEfbu9Vh6RaW",
      },
    ],
  },
  redoc: {
    scripts: [
      {
        path: "bundles/redoc.standalone.js",
        integrity:
          "sha384-w447zOpYfw/1Tv/5AK9NfHTlQIqE3RVR6KY62jCyy9zNDgO64cMwGGP1Fj0zJVf5",
      },
    ],
    styles: [],
  },
  elements: {
    scripts: [
      {
        path: "web-components.min.js",
        integrity:
          "sha384-enyjBaVmV00WFIo0D7AIVgtZ/4x0idVNWHotG8WUpvQo9HXgMSGAAW2YEOpiJTpP",
      },
    ],
    styles: [
      {
        path: "styles.min.css",
        integrity:
          "sha384-iVQBHadsD+eV0M5+ubRCEVXrXEBj+BqcuwjUwPoVJc0Pb1fmrhYSAhL+BFProHdV",
      },
    ],
  },
  rapidoc: {
    scripts: [
      {
        path: "dist/rapidoc-min.js",
        integrity:
          "sha384-HHR6HoZp1auZpg4HHlW1QQNBJOq2gLnEa05IBhNnkE64/gK72hd0kG+TJPmDN3ij",
      },
    ],
    styles: [],
  },
};

/** Files the app serves itself, for self-hosted mode. */
export interface SpecUiAssets {
  readonly scripts: readonly string[];
  readonly styles?: readonly string[];
}

export interface SpecReferenceOptions {
  /** The URL of the document, usually the `specResponse` route. */
  readonly specUrl: string;
  /** Defaults to `scalar`. */
  readonly ui?: SpecUi;
  /** The page title. Defaults to `API reference`. */
  readonly title?: string;
  /**
   * Where the UI loads from. Defaults to jsDelivr at the versions in
   * `SPEC_UI_PACKAGES`, with Subresource Integrity. A string is another CDN
   * with the same package paths (no integrity); `{ scripts, styles }` lists
   * files the app hosts itself.
   */
  readonly assets?: string | SpecUiAssets;
  /** Set on every script and style tag, for a Content Security Policy with nonces. */
  readonly nonce?: string;
  /** UI options: Scalar's configuration, Swagger UI's and Redoc's options, or attributes of the Elements and RapiDoc components. */
  readonly config?: Readonly<Record<string, unknown>>;
}

interface Asset {
  readonly url: string;
  readonly integrity?: string;
}

function assetsOf(
  ui: SpecUi,
  assets: SpecReferenceOptions["assets"],
): { readonly scripts: Asset[]; readonly styles: Asset[] } {
  if (typeof assets === "object") {
    return {
      scripts: assets.scripts.map((url) => ({ url })),
      styles: (assets.styles ?? []).map((url) => ({ url })),
    };
  }

  const { name, version } = SPEC_UI_PACKAGES[ui];
  const base = (assets ?? DEFAULT_CDN).replace(/\/+$/, "");
  const pinned = assets === undefined;

  const toAsset = (file: PinnedFile): Asset => ({
    url: `${base}/${name}@${version}/${file.path}`,
    ...(pinned ? { integrity: file.integrity } : {}),
  });

  return {
    scripts: PINNED[ui].scripts.map(toAsset),
    styles: PINNED[ui].styles.map(toAsset),
  };
}

const HTML_ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

/** Text safe inside an HTML attribute or element. */
function escapeHtml(text: string): string {
  return text.replaceAll(/[&<>"']/g, (char) => HTML_ESCAPES[char] ?? char);
}

/** JSON safe inside an inline `<script>`: no `</script>`, `<!--` or line separators. */
function scriptJson(value: unknown): string {
  return JSON.stringify(value)
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("&", "\\u0026")
    .replaceAll("\u2028", "\\u2028")
    .replaceAll("\u2029", "\\u2029");
}

function attributes(values: Readonly<Record<string, unknown>>): string {
  return Object.entries(values)
    .filter(([, value]) => value !== undefined && value !== false)
    .map(([key, value]) =>
      value === true
        ? ` ${escapeHtml(key)}`
        : ` ${escapeHtml(key)}="${escapeHtml(
            typeof value === "string" ? value : JSON.stringify(value),
          )}"`,
    )
    .join("");
}

function body(ui: SpecUi, specUrl: string, config: Record<string, unknown>) {
  switch (ui) {
    case "scalar": {
      return {
        markup: '<div id="app"></div>',
        init: `Scalar.createApiReference("#app", ${scriptJson({ url: specUrl, ...config })});`,
      };
    }

    case "swagger": {
      return {
        markup: '<div id="swagger-ui"></div>',
        init: `window.ui = SwaggerUIBundle(${scriptJson({ url: specUrl, dom_id: "#swagger-ui", ...config })});`,
      };
    }

    case "redoc": {
      return {
        markup: '<div id="redoc"></div>',
        init: `Redoc.init(${scriptJson(specUrl)}, ${scriptJson(config)}, document.getElementById("redoc"));`,
      };
    }

    case "elements": {
      return {
        markup: `<elements-api${attributes({ apiDescriptionUrl: specUrl, router: "hash", layout: "sidebar", ...config })}></elements-api>`,
      };
    }

    case "rapidoc": {
      return {
        markup: `<rapi-doc${attributes({ "spec-url": specUrl, ...config })}></rapi-doc>`,
      };
    }

    default: {
      const unknown: never = ui;
      throw new TypeError(`Unknown docs UI "${String(unknown)}"`);
    }
  }
}

/**
 * The HTML page of a docs UI for a spec document. Scalar is the default;
 * Swagger UI, Redoc, Stoplight Elements and RapiDoc load the same way.
 *
 * ```ts
 * const html = specReferenceHtml({ specUrl: "/api/openapi.json", ui: "redoc" });
 * ```
 */
export function specReferenceHtml(options: SpecReferenceOptions): string {
  const ui = options.ui ?? "scalar";

  if (!SPEC_UIS.includes(ui)) {
    throw new TypeError(
      `Unknown docs UI "${ui}". Use one of ${SPEC_UIS.join(", ")}.`,
    );
  }

  const { scripts, styles } = assetsOf(ui, options.assets);

  const nonce =
    options.nonce === undefined ? "" : ` nonce="${escapeHtml(options.nonce)}"`;

  const integrity = (asset: Asset): string =>
    asset.integrity === undefined
      ? ""
      : ` integrity="${asset.integrity}" crossorigin="anonymous"`;

  const { markup, init } = body(ui, options.specUrl, { ...options.config });
  const module = ui === "rapidoc" ? ' type="module"' : "";

  return [
    "<!doctype html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escapeHtml(options.title ?? "API reference")}</title>`,
    ...styles.map(
      (style) =>
        `<link rel="stylesheet" href="${escapeHtml(style.url)}"${integrity(style)}${nonce}>`,
    ),
    "</head>",
    "<body>",
    markup,
    ...scripts.map(
      (script) =>
        `<script${module} src="${escapeHtml(script.url)}"${integrity(script)}${nonce}></script>`,
    ),
    ...(init === undefined ? [] : [`<script${nonce}>${init}</script>`]),
    "</body>",
    "</html>",
    "",
  ].join("\n");
}

export interface SpecReferenceResponseOptions extends SpecReferenceOptions {
  /**
   * Sends a Content-Security-Policy that allows the nonce and the asset
   * origins. Generates a nonce when `nonce` is unset.
   */
  readonly csp?: boolean;
  /** Defaults to `no-cache`. */
  readonly cacheControl?: string;
}

function origins(ui: SpecUi, assets: SpecReferenceOptions["assets"]): string[] {
  const { scripts, styles } = assetsOf(ui, assets);
  const found = new Set<string>();

  for (const { url } of [...scripts, ...styles]) {
    if (!/^https?:\/\//.test(url)) {
      continue;
    }

    found.add(new URL(url).origin);
  }

  return [...found];
}

/** The policy `specReference` sends with `csp: true`. */
export function specReferenceCsp(
  options: Pick<SpecReferenceOptions, "ui" | "assets"> & {
    readonly nonce: string;
  },
): string {
  const hosts = origins(options.ui ?? "scalar", options.assets).join(" ");

  const from = (...sources: string[]): string =>
    [...sources, hosts].filter(Boolean).join(" ");

  return [
    "default-src 'none'",
    `script-src ${from(`'nonce-${options.nonce}'`)}`,
    `style-src ${from("'self'", "'unsafe-inline'")}`,
    "img-src 'self' data: https:",
    "font-src 'self' data: https:",
    "connect-src 'self' https:",
    "worker-src 'self' blob:",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'self'",
  ].join("; ");
}

/**
 * A `Response` with the docs UI page for a spec document. Pair it with
 * `specResponse` on the document's route. `GET` and `HEAD` only.
 *
 * ```ts
 * export const GET = (request: Request) =>
 *   specReference({ specUrl: "/api/openapi.json", csp: true }, request);
 * ```
 */
export function specReference(
  options: SpecReferenceResponseOptions,
  request?: Request,
): Response {
  const method = request?.method.toUpperCase() ?? "GET";

  if (method !== "GET" && method !== "HEAD") {
    return methodNotAllowed(["GET", "HEAD"]);
  }

  const nonce =
    options.nonce ??
    (options.csp === true
      ? crypto.randomUUID().replaceAll("-", "")
      : undefined);

  const html = specReferenceHtml({
    ...options,
    ...(nonce === undefined ? {} : { nonce }),
  });

  const headers: Record<string, string> = {
    "content-type": "text/html; charset=utf-8",
    "cache-control": options.cacheControl ?? "no-cache",
  };

  if (options.csp === true && nonce !== undefined) {
    headers["content-security-policy"] = specReferenceCsp({
      nonce,
      ...(options.ui === undefined ? {} : { ui: options.ui }),
      ...(options.assets === undefined ? {} : { assets: options.assets }),
    });
  }

  return new Response(method === "HEAD" ? null : html, {
    status: 200,
    headers,
  });
}

export interface ScalarPresetOptions {
  /** A public OAuth client Scalar's "try it" uses for the authorization code flow. */
  readonly clientId?: string;
  readonly redirectUri?: string;
  /** PKCE for the authorization code flow. Defaults to `SHA-256`. */
  readonly pkce?: "SHA-256" | "plain" | "no";
  /** Scopes Scalar selects by default. */
  readonly defaultScopes?: readonly string[];
  /** `x-scalar-environments`: variables Scalar offers per environment. */
  readonly environments?: Readonly<Record<string, unknown>>;
}

/**
 * Adds Scalar's `x-scalar-*` extensions to an OpenAPI document, so the
 * reference can sign in through the OAuth flows the document declares.
 * Returns a copy. Use it in a `transform`:
 * `transform: ({ document }) => scalarPreset(document, { clientId })`.
 */
export function scalarPreset<D extends object>(
  document: D,
  options: ScalarPresetOptions = {},
): D {
  const copy = structuredClone(document);
  const root: unknown = copy;

  if (!isRecord(root)) {
    return copy;
  }

  if (options.environments !== undefined) {
    root["x-scalar-environments"] = options.environments;
  }

  const components = root["components"];

  const schemes = isRecord(components)
    ? components["securitySchemes"]
    : undefined;

  if (!isRecord(schemes)) {
    return copy;
  }

  for (const scheme of Object.values(schemes)) {
    if (!isRecord(scheme) || scheme["type"] !== "oauth2") {
      continue;
    }

    const flows = scheme["flows"];

    if (!isRecord(flows)) {
      continue;
    }

    for (const [name, flow] of Object.entries(flows)) {
      if (!isRecord(flow)) {
        continue;
      }

      if (options.clientId !== undefined) {
        flow["x-scalar-client-id"] = options.clientId;
      }

      if (options.redirectUri !== undefined) {
        flow["x-scalar-redirect-uri"] = options.redirectUri;
      }

      if (options.defaultScopes !== undefined) {
        flow["x-default-scopes"] = [...options.defaultScopes];
      }

      if (name === "authorizationCode") {
        flow["x-usePkce"] = options.pkce ?? "SHA-256";
      }
    }
  }

  return copy;
}
