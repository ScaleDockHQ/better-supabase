import type { RecordRef } from "../schema/types.ts";

import { bySubjectType, subjectKey } from "./block-subjects.ts";
import { AsyncResult, ok } from "./result.ts";

/** The name and picture one subject type knows for its rows. */
export interface PartyProfile {
  readonly name?: string | undefined;
  readonly avatarUrl?: string | undefined;
}

/**
 * Reads the profile of many rows of one subject type by id: a contacts, people,
 * employees, identities or profiles lookup. A row it leaves out falls back to
 * the subject's label.
 */
export type PartyReader = (
  ids: readonly string[],
) => AsyncResult<Readonly<Record<string, PartyProfile>>>;

/** What `PartyResolver` needs to label a subject whose type has no reader. */
export interface PartyLabel {
  readonly label: string;
  readonly url?: string | undefined;
  readonly found: boolean;
}

/** `subjects.label` as the resolver takes it. */
export type PartyLabeler = (
  refs: readonly RecordRef[],
) => AsyncResult<Readonly<Record<string, PartyLabel>>>;

/** A subject shown as a person or organization: a name and an avatar. */
export interface Party extends RecordRef {
  /** The reader's name, else the subject's label, else the id. */
  readonly name: string;
  /** Up to two letters for an avatar without a picture. */
  readonly initials: string;
  readonly avatarUrl?: string;
  /** The subject's page, when its type has a `url` template. */
  readonly url?: string;
  /** `false` when neither a reader nor the label knew the subject. */
  readonly found: boolean;
}

export interface PartyResolverOptions {
  /** `subjects.label`, which names a subject of any registered type. */
  readonly label: PartyLabeler;
  /**
   * A reader per subject type for the types that hold a name and a picture,
   * keyed by the subject type (`person`, `employee`). A type without one gets
   * its label and no avatar.
   */
  readonly readers?: Readonly<Record<string, PartyReader>>;
}

export interface PartyResolver {
  /**
   * A `Party` for every ref, keyed by `subjectKey` (`type:id`). A ref nothing
   * can name still gets an entry, with `found: false` and its id as the name.
   */
  resolve(
    refs: readonly RecordRef[],
  ): AsyncResult<Readonly<Record<string, Party>>>;
}

/** Up to two upper-case letters from the first words of `name`. */
export function initialsOf(name: string): string {
  const words = name.split(/\s+/u).filter((word) => word !== "");
  const [first] = words;
  const last = words.at(-1);

  if (first === undefined || last === undefined) {
    return "";
  }

  // `.` with the `s` and `u` flags matches one code point, so an emoji or an
  // accented letter is never cut in half.
  const chars = (word: string, count: number): string =>
    (word.match(/./gsu) ?? []).slice(0, count).join("");

  const letters =
    words.length === 1 ? chars(first, 2) : chars(first, 1) + chars(last, 1);

  return letters.toUpperCase();
}

const present = (value: string | undefined): value is string =>
  value !== undefined && value.trim() !== "";

/**
 * One way to show any subject as a name and an avatar (ADR 0831). Contacts,
 * people, employees, identities and profiles each model a person; a page that
 * joins them hands each type's reader to this resolver instead of joining by
 * hand.
 */
export function createPartyResolver(
  options: PartyResolverOptions,
): PartyResolver {
  const readers = options.readers ?? {};

  return {
    resolve: (refs) =>
      AsyncResult.from(async () => {
        const unique = [
          ...new Map(refs.map((ref) => [subjectKey(ref), ref])).values(),
        ];

        const [labels, profiles] = await Promise.all([
          options.label(unique),
          bySubjectType<PartyProfile>(unique, (type, ids) => {
            const read = Object.hasOwn(readers, type)
              ? readers[type]
              : undefined;

            return read === undefined
              ? AsyncResult.from(() => Promise.resolve(ok({})))
              : read(ids);
          }),
        ]);

        if (!labels.ok) {
          return labels;
        }

        if (!profiles.ok) {
          return profiles;
        }

        const parties: Record<string, Party> = {};

        for (const ref of unique) {
          const key = subjectKey(ref);
          const labelled = labels.data[key];

          const profile = Object.hasOwn(profiles.data, key)
            ? profiles.data[key]
            : undefined;

          const read = profile?.name;
          const name = present(read) ? read : labelled?.label;
          const found = present(read) || labelled?.found === true;
          const shown = present(name) ? name : ref.id;

          parties[key] = {
            type: ref.type,
            id: ref.id,
            name: shown,
            initials: initialsOf(shown),
            ...(present(profile?.avatarUrl)
              ? { avatarUrl: profile.avatarUrl }
              : {}),
            ...(labelled?.url === undefined ? {} : { url: labelled.url }),
            found,
          };
        }

        return ok(parties);
      }),
  };
}
