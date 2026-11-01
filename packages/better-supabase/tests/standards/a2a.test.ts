import { describe, expect, it } from "vitest";

import {
  A2A_CARD_PATH,
  A2A_PROTOCOL_VERSION,
  agentCard,
  taskStateOf,
} from "../../src/blocks/agents/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("A2A 1.0", () => {
  it("pins the protocol version the card and endpoint speak", () => {
    expect(A2A_PROTOCOL_VERSION).toBe(SPEC_PINS.a2a);
    expect(A2A_CARD_PATH).toBe("/.well-known/agent-card.json");
  });

  it("writes the card fields the proto marks required", () => {
    const card = agentCard(
      [
        {
          slug: "writer",
          name: "Writer",
          description: "Writes",
          tools: [],
          starters: [],
          visibility: "public",
        },
      ],
      {
        name: "Acme",
        description: "Agents",
        version: "1",
        url: "https://acme.test/a2a",
      },
    );

    expect(card).toMatchObject({
      name: "Acme",
      description: "Agents",
      version: "1",
      supportedInterfaces: [
        { protocolBinding: "JSONRPC", protocolVersion: "1.0" },
      ],
      capabilities: { streaming: true },
      defaultInputModes: ["text/plain"],
      defaultOutputModes: ["text/plain"],
      skills: [{ id: "writer", name: "Writer", tags: ["agent"] }],
    });
  });

  it("spells canceled with one l", () => {
    expect(taskStateOf("cancelled")).toBe("TASK_STATE_CANCELED");
  });
});
