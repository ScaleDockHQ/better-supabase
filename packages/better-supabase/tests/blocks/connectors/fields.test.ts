import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import { createConnectors } from "../../../src/blocks/connectors/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-01-01T00:00:00Z";

const ROW = {
  id: "s1",
  organization_id: "o1",
  name: "GitHub",
  url: "https://mcp.example.com",
  transport: "http",
  auth_type: "none",
  credential_ref: null,
  scopes: [],
  client_metadata: {},
  enabled: true,
  grant: null,
  created_at: AT,
  updated_at: AT,
  fields: { region: "eu" },
};

const Fields = v.object({ region: v.picklist(["eu", "us"]) });

describe("connectors fields", () => {
  it("sends the extra fields with the server's own and parses every read", async () => {
    const t = fieldsTransport({
      save_connector_server: () => ROW,
      list_connector_servers: () => [ROW, ROW],
      get_connector: () => ROW,
    });

    const connectors = createConnectors({ transport: t, fields: Fields });

    const created = await connectors.servers
      .create({
        organizationId: "o1",
        server: {
          name: "GitHub",
          url: "https://mcp.example.com",
          authType: "none",
          fields: { region: "eu" },
        },
      })
      .orThrow();

    expectTypeOf(created.fields.region).toEqualTypeOf<"eu" | "us">();
    expect(created.fields).toEqual({ region: "eu" });
    expect(t.calls[0]?.[1]["fields"]).toEqual({
      region: "eu",
      name: "GitHub",
      url: "https://mcp.example.com",
      auth_type: "none",
    });
    await connectors.servers
      .update({
        organizationId: "o1",
        serverId: "s1",
        fields: { fields: { region: "us" } },
      })
      .orThrow();
    expect(t.calls[1]?.[1]["fields"]).toEqual({ region: "us" });
    const list = await connectors.servers.list("o1").orThrow();
    expect(list.map((server) => server.fields.region)).toEqual(["eu", "eu"]);
    expect(
      (await connectors.servers.get({ serverId: "s1" }).orThrow()).fields,
    ).toEqual({ region: "eu" });
  });

  it("refuses a bad field before the call and a bad row after it", async () => {
    const t = fieldsTransport({
      get_connector: () => ({ ...ROW, fields: { region: "mars" } }),
    });

    const connectors = createConnectors({ transport: t, fields: Fields });

    const updated = await connectors.servers.update({
      organizationId: "o1",
      serverId: "s1",
      fields: { fields: { region: "mars" as never } },
    });

    expect(updated.ok ? undefined : updated.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
    const got = await connectors.servers.get({ serverId: "s1" });
    expect(got.ok ? undefined : got.error.kind).toBe("validation");
  });
});
