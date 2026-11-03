import type { ProviderReference } from "ai";

import { uploadSkill } from "ai";

import type {
  Agents,
  AgentSkill,
  AgentSkillProviderRef,
} from "../../blocks/agents/agents.ts";
import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

/**
 * The bytes of one Storage object a skill keeps, such as `download` on a
 * bucket.
 */
export type ReadSkillFile = (object: string) => Promise<Uint8Array | string>;

export interface SyncSkillOptions {
  readonly skill: AgentSkill;
  /** The agents client, with the service role: it stores the new reference. */
  readonly agents: Pick<Agents, "recordSkillSync">;
  /** `anthropic.skills()`, `openai.skills()` or a provider. */
  readonly api: SkillsApi;
  /** The provider name the reference is stored under, such as `anthropic`. */
  readonly provider: string;
  /** Reads a skill file from Storage. */
  readonly read: ReadSkillFile;
  readonly displayTitle?: string;
  readonly providerOptions?: Record<string, Record<string, unknown>>;
  readonly abortSignal?: AbortSignal;
}

export interface SyncedSkill {
  /** `false` when the stored reference was already for the current hash. */
  readonly uploaded: boolean;
  readonly provider: string;
  readonly reference: Readonly<Record<string, unknown>>;
  readonly contentHash: string;
}

/**
 * `anthropic.skills()`, `openai.skills()` or a provider, as `uploadSkill`
 * takes.
 */
export type SkillsApi = Parameters<typeof uploadSkill>[0]["api"];

const encoder = new TextEncoder();

function bytesOf(value: Uint8Array | string): Uint8Array {
  return typeof value === "string" ? encoder.encode(value) : value;
}

async function sha256(parts: readonly Uint8Array[]): Promise<string> {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const joined = new Uint8Array(total);
  let at = 0;

  for (const part of parts) {
    joined.set(part, at);
    at += part.length;
  }

  const digest = await crypto.subtle.digest("SHA-256", joined);

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Uploads a skill's files to a provider when their content changed, and stores
 * the returned `providerReference`. The hash covers each path and its bytes, so
 * a rename uploads again and an unchanged skill costs no call to the provider.
 */
export function syncSkill(options: SyncSkillOptions): AsyncResult<SyncedSkill> {
  return AsyncResult.from(async (): Promise<Result<SyncedSkill>> => {
    const { skill } = options;
    const files = skill.files ?? [];

    if (files.length === 0) {
      return err(
        dbError("invalid_input", "the skill has no files to upload", {
          hint: "SKILL_NO_FILES",
        }),
      );
    }

    const loaded = await Promise.all(
      files.map(async (file) => ({
        path: file.path,
        bytes: bytesOf(await options.read(file.object)),
      })),
    );

    const ordered = loaded.toSorted((a, b) => a.path.localeCompare(b.path));

    const contentHash = await sha256(
      ordered.flatMap((file) => [encoder.encode(`${file.path}\n`), file.bytes]),
    );

    const stored = skill.providerRefs?.[options.provider];

    if (stored?.contentHash === contentHash) {
      return ok({
        uploaded: false,
        provider: options.provider,
        reference: stored.reference,
        contentHash,
      });
    }

    // SAFETY: abortSignal is accepted by the call options at runtime but absent from the declared type.
    const { providerReference } = await uploadSkill({
      api: options.api,
      files: ordered.map((file) => ({ path: file.path, data: file.bytes })),
      displayTitle: options.displayTitle ?? skill.name ?? skill.id,
      ...(options.providerOptions
        ? { providerOptions: options.providerOptions }
        : {}),
      ...(options.abortSignal ? { abortSignal: options.abortSignal } : {}),
    } as Parameters<typeof uploadSkill>[0]);

    const recorded = await options.agents.recordSkillSync({
      skillId: skill.id,
      provider: options.provider,
      reference: providerReference,
      contentHash,
    });

    if (!recorded.ok) {
      return err(recorded.error);
    }

    return ok({
      uploaded: true,
      provider: options.provider,
      reference: providerReference,
      contentHash,
    });
  });
}

type StoredRefs = Readonly<Record<string, AgentSkillProviderRef>>;

function referenceOf(
  skill: { readonly providerRefs?: StoredRefs },
  provider: string,
): ProviderReference | undefined {
  const reference = skill.providerRefs?.[provider]?.reference;

  // SAFETY: syncSkill stored a ProviderReference (provider name to id) here.
  return reference as ProviderReference | undefined;
}

/**
 * `providerOptions.anthropic` for a call that loads the skills in a container:
 * `container.skills` holds one custom entry per synced skill.
 */
export function anthropicSkillOptions(
  skills: readonly { readonly providerRefs?: StoredRefs }[],
  provider = "anthropic",
): {
  anthropic: {
    container: {
      skills: { type: "custom"; providerReference: ProviderReference }[];
    };
  };
} {
  return {
    anthropic: {
      container: {
        skills: skills.flatMap((skill) => {
          const providerReference = referenceOf(skill, provider);

          return providerReference
            ? [{ type: "custom" as const, providerReference }]
            : [];
        }),
      },
    },
  };
}

/** The `skills` array of an OpenAI shell tool's `containerAuto` environment. */
export function openaiShellSkills(
  skills: readonly { readonly providerRefs?: StoredRefs }[],
  provider = "openai",
): { type: "skillReference"; providerReference: ProviderReference }[] {
  return skills.flatMap((skill) => {
    const providerReference = referenceOf(skill, provider);

    return providerReference
      ? [{ type: "skillReference" as const, providerReference }]
      : [];
  });
}

/** One skill as `HarnessAgent` takes it. */
export interface HarnessSkill {
  readonly name: string;
  readonly description: string;
  readonly content: string;
  readonly files: readonly {
    readonly path: string;
    readonly content: string;
  }[];
}

/**
 * Turns the skills an agent stores into the inline skills `HarnessAgent` takes:
 * `SKILL.md` becomes `content` and the other text files follow it.
 */
export async function harnessSkills(
  skills: readonly AgentSkill[],
  read: ReadSkillFile,
): Promise<readonly HarnessSkill[]> {
  const decoder = new TextDecoder();

  const text = async (object: string): Promise<string> => {
    const value = await read(object);

    return typeof value === "string" ? value : decoder.decode(value);
  };

  return Promise.all(
    skills.flatMap((skill) => {
      const files = skill.files ?? [];
      const main = files.find((file) => /(^|\/)SKILL\.md$/i.test(file.path));

      if (!main) {
        return [];
      }

      return [
        (async (): Promise<HarnessSkill> => {
          const description = skill.reference["description"];

          return {
            name: skill.name ?? skill.id,
            description:
              typeof description === "string"
                ? description
                : (skill.name ?? skill.id),
            content: await text(main.object),
            files: await Promise.all(
              files
                .filter((file) => file !== main)
                .map(async (file) => ({
                  path: file.path,
                  content: await text(file.object),
                })),
            ),
          };
        })(),
      ];
    }),
  );
}
