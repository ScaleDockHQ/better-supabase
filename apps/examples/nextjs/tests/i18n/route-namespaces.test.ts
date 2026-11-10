import { relative } from "node:path";
import { describe, expect, it } from "vitest";

import {
  allRouteFiles,
  APP,
  clientNamespaces,
  effectiveNamespaces,
  sorted,
} from "./route-graph";

/**
 * A client component reads its messages from the nearest `RouteMessages`
 * provider. A namespace the provider leaves out renders the raw key, so every
 * route file's client islands must read only namespaces its provider lists.
 */
describe("route message namespaces", () => {
  const files = allRouteFiles();

  it("finds the route files", () => {
    expect(files.length).toBeGreaterThan(100);
  });

  it("covers every namespace a route's client components read", () => {
    const missing = files.flatMap((file) => {
      const { from, namespaces } = effectiveNamespaces(file);

      const lacking = sorted(clientNamespaces(file)).filter(
        (namespace) => !namespaces.includes(namespace),
      );

      return lacking.length > 0
        ? [
            `${relative(APP, file)} reads ${lacking.join(", ")} (provider: ${from})`,
          ]
        : [];
    });

    expect(
      missing,
      "add the namespace to the nearest layout's <RouteMessages namespaces>",
    ).toEqual([]);
  });
});
