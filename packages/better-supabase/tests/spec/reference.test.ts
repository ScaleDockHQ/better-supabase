import { describe, expect, it } from "vitest";

import {
  SPEC_UI_PACKAGES,
  SPEC_UIS,
  scalarPreset,
  specReference,
  specReferenceCsp,
  specReferenceHtml,
} from "../../src/spec/index.ts";

describe("specReferenceHtml", () => {
  it.each(SPEC_UIS)("pins %s on jsDelivr with Subresource Integrity", (ui) => {
    const html = specReferenceHtml({ specUrl: "/api/openapi.json", ui });
    const { name, version } = SPEC_UI_PACKAGES[ui];
    expect(html).toContain(`https://cdn.jsdelivr.net/npm/${name}@${version}/`);
    expect(html).toMatch(/integrity="sha384-[\w+/=]+" crossorigin="anonymous"/);
    expect(html).toContain("/api/openapi.json");
  });

  it("defaults to Scalar and escapes the title and the config", () => {
    const html = specReferenceHtml({
      specUrl: "/openapi.json",
      title: "<CRM> & co",
      config: { theme: "</script><script>alert(1)" },
    });

    expect(html).toContain("<title>&lt;CRM&gt; &amp; co</title>");
    expect(html).toContain("Scalar.createApiReference");
    expect(html).not.toContain("</script><script>alert");
  });

  it("loads from another CDN or self-hosted files, with a nonce", () => {
    const cdn = specReferenceHtml({
      specUrl: "/o.json",
      ui: "swagger",
      assets: "https://unpkg.com/",
    });

    expect(cdn).toContain("https://unpkg.com/swagger-ui-dist@");
    expect(cdn).not.toContain("integrity=");

    const local = specReferenceHtml({
      specUrl: "/o.json",
      ui: "elements",
      assets: {
        scripts: ["/docs/elements.js"],
        styles: ["/docs/elements.css"],
      },
      nonce: "abc",
      config: { hideTryIt: true, layout: "stacked", basePath: undefined },
    });

    expect(local).toContain('<script src="/docs/elements.js" nonce="abc">');
    expect(local).toContain(
      '<link rel="stylesheet" href="/docs/elements.css" nonce="abc">',
    );
    expect(local).toContain('layout="stacked"');
    expect(local).toContain(" hideTryIt");
    expect(
      specReferenceHtml({
        specUrl: "/o.json",
        ui: "rapidoc",
        config: { "render-style": { a: 1 } },
      }),
    ).toContain('render-style="{&quot;a&quot;:1}"');
  });

  it("rejects an unknown UI", () => {
    expect(() =>
      specReferenceHtml({ specUrl: "/o.json", ui: "nope" as never }),
    ).toThrow('Unknown docs UI "nope"');
  });
});

describe("specReference", () => {
  it("serves the page with a nonce-based policy", async () => {
    const response = specReference({ specUrl: "/o.json", csp: true });
    expect(response.headers.get("content-type")).toBe(
      "text/html; charset=utf-8",
    );
    expect(response.headers.get("cache-control")).toBe("no-cache");
    const policy = response.headers.get("content-security-policy") ?? "";
    const nonce = /'nonce-(\w+)'/.exec(policy)?.[1];
    expect(nonce).toBeDefined();
    expect(policy).toContain("https://cdn.jsdelivr.net");
    expect(await response.text()).toContain(`nonce="${nonce}"`);
  });

  it("answers HEAD without a body and refuses other methods", async () => {
    const head = specReference(
      { specUrl: "/o.json", cacheControl: "public, max-age=60" },
      new Request("https://x.test/docs", { method: "HEAD" }),
    );

    expect(head.headers.get("cache-control")).toBe("public, max-age=60");
    expect(head.headers.get("content-security-policy")).toBeNull();
    expect(await head.text()).toBe("");

    const post = specReference(
      { specUrl: "/o.json" },
      new Request("https://x.test/docs", { method: "POST" }),
    );

    expect(post.status).toBe(405);
    expect(post.headers.get("allow")).toBe("GET, HEAD");
  });

  it("lists only remote origins in the policy", () => {
    const policy = specReferenceCsp({
      nonce: "n",
      ui: "redoc",
      assets: { scripts: ["/redoc.js"] },
    });

    expect(policy).toContain("script-src 'nonce-n';");
    expect(policy).not.toContain("jsdelivr");
  });
});

describe("scalarPreset", () => {
  const document = {
    openapi: "3.1.2",
    components: {
      securitySchemes: {
        oauth: {
          type: "oauth2",
          flows: {
            authorizationCode: {
              authorizationUrl: "https://a",
              tokenUrl: "https://t",
              scopes: {},
            },
            clientCredentials: { tokenUrl: "https://t", scopes: {} },
          },
        },
        bearer: { type: "http", scheme: "bearer" },
      },
    },
  };

  it("adds the Scalar OAuth extensions to a copy", () => {
    const result = scalarPreset(document, {
      clientId: "docs",
      redirectUri: "https://docs.test/callback",
      defaultScopes: ["read"],
      environments: { production: { variables: {} } },
    });

    expect(result).not.toBe(document);
    expect(result).toMatchObject({
      "x-scalar-environments": { production: { variables: {} } },
      components: {
        securitySchemes: {
          oauth: {
            flows: {
              authorizationCode: {
                "x-scalar-client-id": "docs",
                "x-scalar-redirect-uri": "https://docs.test/callback",
                "x-default-scopes": ["read"],
                "x-usePkce": "SHA-256",
              },
              clientCredentials: { "x-scalar-client-id": "docs" },
            },
          },
        },
      },
    });
    expect(
      document.components.securitySchemes.oauth.flows.authorizationCode,
    ).not.toHaveProperty("x-usePkce");
  });

  it("leaves documents without OAuth flows alone", () => {
    expect(scalarPreset({ openapi: "3.1.2" })).toEqual({ openapi: "3.1.2" });
    expect(
      scalarPreset(
        { components: { securitySchemes: { a: { type: "oauth2" } } } },
        { pkce: "no" },
      ),
    ).toEqual({ components: { securitySchemes: { a: { type: "oauth2" } } } });
  });
});
