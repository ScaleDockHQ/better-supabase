import { describe, expect, it } from "vitest";

import {
  checkCoverage,
  checkEntityRoutes,
  routeExists,
} from "./check-example-coverage.ts";

describe("check-example-coverage", () => {
  it("passes for the catalog and the presets", () => {
    expect(checkCoverage().problems).toEqual([]);
  });

  it("reports a block without an entry", () => {
    const report = checkCoverage(["audit", "not-a-block"]);

    expect(report.problems).toContain(
      'Block "not-a-block" has no entry in block-coverage.ts',
    );
  });

  it("reports a route without a page", () => {
    expect(routeExists("/customers")).toBe(true);
    expect(routeExists("/does-not-exist")).toBe(false);
  });

  it("lists the route of every declared entity page under its block", () => {
    expect(checkEntityRoutes()).toEqual([]);
  });

  it("reports a declared page the map does not list", () => {
    const page = {
      entity: "risks.risk",
      name: "risks",
      route: "/risks",
      messageKeys: [],
    };

    expect(checkEntityRoutes([page], { risks: { routes: [] } })).toEqual([
      'Entity page risks.risk (/risks) is not listed under block "risks" in block-coverage.ts',
    ]);

    expect(checkEntityRoutes([page], {})).toEqual([
      'Entity page risks.risk has no entry for block "risks" in block-coverage.ts',
    ]);
  });

  it("needs no map entry for an app entity, only its page", () => {
    const page = {
      entity: "app.customers",
      name: "customers",
      route: "/customers",
      messageKeys: [],
    };

    expect(checkEntityRoutes([page], {})).toEqual([]);

    expect(
      checkEntityRoutes([{ ...page, route: "/does-not-exist" }], {}),
    ).toEqual([
      "Entity page app.customers lists /does-not-exist, which has no page.tsx",
    ]);
  });
});
