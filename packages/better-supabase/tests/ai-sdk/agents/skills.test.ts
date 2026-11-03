import { describe, expect, it } from "vitest";

import type { AgentSkill } from "../../../src/blocks/agents/agents.ts";

import {
  anthropicSkillOptions,
  harnessSkills,
  openaiShellSkills,
  syncSkill,
} from "../../../src/ai-sdk/agents/skills.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const objects: Record<string, string> = {
  "s/SKILL.md": "# Skill",
  "s/ref.md": "reference",
};

const read = async (object: string): Promise<string> => objects[object] ?? "";

function fakeApi() {
  const uploads: unknown[] = [];

  const api = {
    specificationVersion: "v4",
    async uploadSkill(options: unknown) {
      uploads.push(options);

      return { providerReference: { anthropic: "skill_1" }, warnings: [] };
    },
  };

  return { api, uploads };
}

const skill: AgentSkill = {
  id: "k1",
  provider: "anthropic",
  reference: { description: "Does a thing" },
  name: "thing",
  files: [
    { path: "thing/SKILL.md", object: "s/SKILL.md" },
    { path: "thing/ref.md", object: "s/ref.md" },
  ],
};

describe("syncSkill", () => {
  it("uploads once, then skips while the hash is unchanged", async () => {
    const { api, uploads } = fakeApi();
    const recorded: unknown[] = [];

    const agents = {
      recordSkillSync: (input: { contentHash: string }) => {
        recorded.push(input);

        return AsyncResult.ok({});
      },
    };

    const first = await syncSkill({
      skill,
      agents,
      // SAFETY: a fake that implements only uploadSkill.
      api: api as never,
      provider: "anthropic",
      read,
    }).orThrow();

    expect(first.uploaded).toBe(true);
    expect(uploads).toHaveLength(1);
    expect(recorded).toHaveLength(1);

    const second = await syncSkill({
      skill: {
        ...skill,
        providerRefs: {
          anthropic: {
            reference: first.reference,
            contentHash: first.contentHash,
          },
        },
      },
      agents,
      api: api as never,
      provider: "anthropic",
      read,
    }).orThrow();

    expect(second.uploaded).toBe(false);
    expect(uploads).toHaveLength(1);
  });

  it("uploads again when a file changes", async () => {
    const { api, uploads } = fakeApi();

    const agents = { recordSkillSync: () => AsyncResult.ok({}) };

    const base = await syncSkill({
      skill,
      agents,
      api: api as never,
      provider: "anthropic",
      read,
    }).orThrow();

    await syncSkill({
      skill: {
        ...skill,
        providerRefs: {
          anthropic: {
            reference: base.reference,
            contentHash: base.contentHash,
          },
        },
      },
      agents,
      api: api as never,
      provider: "anthropic",
      read: async (object) => `${await read(object)} changed`,
    }).orThrow();

    expect(uploads).toHaveLength(2);
  });

  it("returns an error for a skill without files", async () => {
    const { api } = fakeApi();

    const result = await syncSkill({
      skill: { ...skill, files: [] },
      agents: { recordSkillSync: () => AsyncResult.ok({}) },
      api: api as never,
      provider: "anthropic",
      read,
    });

    expect(result.ok).toBe(false);
  });
});

describe("skill provider helpers", () => {
  const synced = {
    providerRefs: {
      anthropic: { reference: { anthropic: "skill_1" }, contentHash: "h" },
      openai: { reference: { openai: "skill_2" }, contentHash: "h" },
    },
  };

  it("fills container.skills for Anthropic and the OpenAI shell environment", () => {
    expect(anthropicSkillOptions([synced, {}])).toEqual({
      anthropic: {
        container: {
          skills: [
            { type: "custom", providerReference: { anthropic: "skill_1" } },
          ],
        },
      },
    });

    expect(openaiShellSkills([synced])).toEqual([
      { type: "skillReference", providerReference: { openai: "skill_2" } },
    ]);
  });

  it("turns stored files into harness skills", async () => {
    expect(await harnessSkills([skill], read)).toEqual([
      {
        name: "thing",
        description: "Does a thing",
        content: "# Skill",
        files: [{ path: "thing/ref.md", content: "reference" }],
      },
    ]);
  });
});
