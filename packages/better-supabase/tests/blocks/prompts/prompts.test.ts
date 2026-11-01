import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createPrompts,
  renderPrompt,
} from "../../../src/blocks/prompts/index.ts";

const AT = "2026-01-01T00:00:00Z";

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "p1",
  organization_id: null,
  name: "greet",
  version: 2,
  template: "Hello {{name}}",
  variables: ["name"],
  created_at: AT,
  ...overrides,
});

function fake(
  handlers: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];

      return handler
        ? Promise.resolve(handler(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };

  return { transport, calls };
}

describe("renderPrompt", () => {
  it("fills placeholders as text", () => {
    expect(renderPrompt("Hi {{ name }}, {{name}}!", { name: "{{x}}" })).toBe(
      "Hi {{x}}, {{x}}!",
    );
  });

  it("throws on a missing or unused variable", () => {
    expect(() => renderPrompt("Hi {{name}}", {})).toThrow(/name/);
    expect(() => renderPrompt("Hi", { name: "a" })).toThrow(/name/);
  });
});

describe("createPrompts", () => {
  it("creates with the placeholders as variables", async () => {
    const { transport, calls } = fake({ create_prompt_version: () => row() });

    const saved = await createPrompts({ transport }).create({
      name: "greet",
      template: "Hello {{name}}",
      label: "production",
    });

    expect(saved.ok).toBe(true);
    expect(calls[0]?.args).toMatchObject({
      name: "greet",
      variables: ["name"],
      label: "production",
    });
  });

  it("reads production by default and renders", async () => {
    const { transport, calls } = fake({ get_prompt: () => row() });

    const got = await createPrompts({ transport })
      .get({ name: "greet" })
      .orThrow();

    expect(calls[0]?.args).toMatchObject({ label: "production" });
    expect(got?.render({ name: "Ada" })).toBe("Hello Ada");
  });

  it("returns undefined for a missing prompt", async () => {
    const { transport } = fake({ get_prompt: () => null });

    const got = await createPrompts({ transport })
      .get({ name: "nope" })
      .orThrow();

    expect(got).toBeUndefined();
  });

  it("lists versions with labels", async () => {
    const { transport } = fake({
      list_prompt_versions: () => [row({ labels: ["production"] })],
    });

    const list = await createPrompts({ transport })
      .versions({ name: "greet" })
      .orThrow();

    expect(list[0]?.labels).toEqual(["production"]);
  });
});
