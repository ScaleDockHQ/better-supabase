import { describe, expect, test } from "vitest";

import {
  absoluteUrl,
  breadcrumbList,
  faqPage,
  homeGraph,
  howTo,
  itemList,
} from "../../lib/structured-data";

const BASE = "https://example.com";

describe("structured data", () => {
  test("absoluteUrl resolves paths and keeps absolute URLs", () => {
    expect(absoluteUrl("/blocks", BASE)).toBe("https://example.com/blocks");
    expect(absoluteUrl("https://other.dev/x", BASE)).toBe(
      "https://other.dev/x",
    );
  });

  test("lists number their items from 1", () => {
    const crumbs = breadcrumbList([
      { name: "Home", href: `${BASE}/` },
      { name: "Blocks", href: `${BASE}/blocks` },
    ]);

    expect(crumbs).toMatchObject({
      "@type": "BreadcrumbList",
      itemListElement: [{ position: 1 }, { position: 2, name: "Blocks" }],
    });

    expect(itemList("Blocks", [{ name: "A", url: `${BASE}/a` }])).toMatchObject(
      { numberOfItems: 1, itemListElement: [{ position: 1, name: "A" }] },
    );
  });

  test("the home graph links the site and package to one publisher", () => {
    const graph = homeGraph({
      name: "better-supabase",
      url: BASE,
      description: "A typed layer.",
      github: "https://github.com/acme/x",
      npm: "https://npmjs.com/package/x",
      company: { name: "Acme", url: "https://acme.dev" },
      runtimes: ["Node.js", "Deno"],
      frameworks: ["Next.js", "Hono"],
    });

    const publisher = { "@id": "https://acme.dev#organization" };

    expect(graph).toMatchObject({
      "@graph": [
        { "@type": "Organization", ...publisher },
        { "@type": "WebSite", publisher },
        {
          "@type": "SoftwareSourceCode",
          author: publisher,
          runtimePlatform: ["Node.js", "Deno"],
          keywords: "Next.js, Hono",
        },
      ],
    });
  });

  test("faqPage and howTo keep the order they get", () => {
    expect(faqPage([{ question: "Q?", answer: "A." }]).mainEntity).toEqual([
      {
        "@type": "Question",
        name: "Q?",
        acceptedAnswer: { "@type": "Answer", text: "A." },
      },
    ]);

    const recipe = howTo({
      name: "Bell",
      description: "A bell.",
      url: `${BASE}/recipes/bell`,
      image: null,
      steps: [
        { name: "Install", text: "Run it." },
        { name: "Render", text: "Use it." },
      ],
    });

    expect(JSON.stringify(recipe)).not.toContain('"image"');
    expect(recipe.step).toMatchObject([{ position: 1 }, { position: 2 }]);
  });
});
