/**
 * schema.org graphs for the JSON-LD on each page. They take every URL and
 * value as an argument, so they stay pure and the tests need no env.
 * `JSON.stringify` drops the properties that are `undefined`.
 */

export interface Crumb {
  readonly name: string;
  readonly href: string;
}

const CONTEXT = "https://schema.org";

/** `path` on `base`, keeping an absolute URL as it is. */
export function absoluteUrl(path: string, base: string): string {
  return new URL(path, base).toString();
}

export function breadcrumbList(items: readonly Crumb[]) {
  return {
    "@context": CONTEXT,
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: item.href,
    })),
  };
}

export interface SiteFacts {
  readonly name: string;
  readonly url: string;
  readonly description: string;
  readonly github: string;
  readonly npm: string;
  readonly company: { readonly name: string; readonly url: string };
}

/** The home page graph: the publisher, the site and the package. */
export function homeGraph(site: SiteFacts) {
  const organizationId = `${site.company.url}#organization`;

  return {
    "@context": CONTEXT,
    "@graph": [
      {
        "@type": "Organization",
        "@id": organizationId,
        name: site.company.name,
        url: site.company.url,
      },
      {
        "@type": "WebSite",
        "@id": `${site.url}#website`,
        name: site.name,
        url: site.url,
        description: site.description,
        publisher: { "@id": organizationId },
      },
      {
        "@type": "SoftwareSourceCode",
        name: site.name,
        description: site.description,
        url: site.url,
        codeRepository: site.github,
        programmingLanguage: ["TypeScript", "SQL"],
        runtimePlatform: "Node.js",
        license: "https://opensource.org/licenses/MIT",
        sameAs: [site.github, site.npm],
        author: { "@id": organizationId },
      },
    ],
  };
}

export function faqPage(
  entries: readonly { question: string; answer: string }[],
) {
  return {
    "@context": CONTEXT,
    "@type": "FAQPage",
    mainEntity: entries.map((entry) => ({
      "@type": "Question",
      name: entry.question,
      acceptedAnswer: { "@type": "Answer", text: entry.answer },
    })),
  };
}

/** An index page as a list of the pages it links to. */
export function itemList(
  name: string,
  items: readonly { name: string; url: string }[],
) {
  return {
    "@context": CONTEXT,
    "@type": "ItemList",
    name,
    numberOfItems: items.length,
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      url: item.url,
    })),
  };
}

/** A block page: the module as a piece of source code in the package. */
export function blockSource(block: {
  name: string;
  title: string;
  description: string;
  url: string;
  docs: string;
  repository: string;
}) {
  return {
    "@context": CONTEXT,
    "@type": "SoftwareSourceCode",
    name: `${block.title} block`,
    alternateName: block.name,
    description: block.description,
    url: block.url,
    codeRepository: block.repository,
    programmingLanguage: ["SQL", "TypeScript"],
    isPartOf: { "@type": "SoftwareSourceCode", name: "better-supabase" },
    subjectOf: { "@type": "TechArticle", url: block.docs },
  };
}

/** A recipe page as the steps it walks through. */
export function howTo(recipe: {
  name: string;
  description: string;
  url: string;
  image: string | null;
  steps: readonly { name: string; text: string }[];
}) {
  return {
    "@context": CONTEXT,
    "@type": "HowTo",
    name: recipe.name,
    description: recipe.description,
    url: recipe.url,
    image: recipe.image ?? undefined,
    step: recipe.steps.map((step, index) => ({
      "@type": "HowToStep",
      position: index + 1,
      name: step.name,
      text: step.text,
    })),
  };
}
