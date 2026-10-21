import type { DbError } from "../../core/errors.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Tag, Tags } from "./tags.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok, type Result, toDbError } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/** A tag change on the subject that committed, for `onChanged`. */
export type TagChange =
  | { readonly kind: "added"; readonly tag: Tag; readonly created: boolean }
  | { readonly kind: "removed"; readonly tag: Tag };

export interface TagInputControllerOptions {
  readonly client: Pick<
    Tags,
    "list" | "forSubject" | "tag" | "untag" | "create"
  >;
  readonly auth: AuthPort;
  /** The organization; the input waits without one. */
  readonly organizationId: string | null;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The kind of tags the input offers and creates, such as `customer`. */
  readonly kind: string;
  /** Runs after a tag was added or removed. A throw is kept in `error`. */
  readonly onChanged?: (change: TagChange) => void | Promise<void>;
}

export interface TagInputSnapshot {
  /** The subject's tags, in rank order; `undefined` until the first load. */
  readonly tags: readonly Tag[] | undefined;
  /** Every tag of the kind, for suggestions; `undefined` until the first load. */
  readonly available: readonly Tag[] | undefined;
  /** The tag ids, or the names of tags being created, with a write in flight. */
  readonly pending: readonly string[];
  readonly error: DbError | undefined;
}

export interface TagInputActions {
  /** Adds an existing tag, shown at once and taken back when it fails. */
  readonly add: (tagId: string) => Promise<Result<Tag>>;
  /** Removes a tag, hidden at once and put back when it fails. */
  readonly remove: (tagId: string) => Promise<Result<boolean>>;
  /**
   * Adds the tag called `name`: an existing one of the kind with the same name
   * (ignoring case), or a new one, which needs `tags.manage`.
   */
  readonly create: (name: string) => Promise<Result<Tag>>;
  readonly refresh: () => Promise<void>;
}

export type TagInputController = Controller<TagInputSnapshot, TagInputActions>;

const without = (list: readonly string[], id: string): readonly string[] =>
  list.filter((each) => each !== id);

const noOrganization = (): Result<never> =>
  err(dbError("invalid_input", "No organization is active"));

/**
 * One subject's tags for a tag input: the tags on it, every tag of the kind for
 * suggestions, and `add`, `remove` and `create`, which show the change at
 * once.
 */
export function createTagInputController(
  options: TagInputControllerOptions,
): TagInputController {
  const { client, organizationId, subjectType, subjectId, kind } = options;

  return defineController<TagInputSnapshot, TagInputActions>(
    { tags: undefined, available: undefined, pending: [], error: undefined },
    (state) => {
      let ticket = 0;

      const refresh = async (): Promise<void> => {
        if (organizationId === null) {
          return;
        }

        const request = ++ticket;

        const [tags, available] = await Promise.all([
          client.forSubject(organizationId, subjectType, subjectId),
          client.list(organizationId, kind),
        ]);

        if (request !== ticket) {
          return;
        }

        if (tags.ok && available.ok) {
          state.set({
            tags: tags.data,
            available: available.data,
            error: undefined,
          });
        } else {
          state.set({ error: tags.error ?? available.error ?? undefined });
        }
      };

      const changed = async (change: TagChange): Promise<void> => {
        try {
          await options.onChanged?.(change);
        } catch (cause) {
          state.set({ error: toDbError(cause) });
        }
      };

      const apply = async (
        tag: Tag,
        created: boolean,
      ): Promise<Result<Tag>> => {
        if (organizationId === null) {
          return noOrganization();
        }

        // A load that started before the change would answer without it.
        ticket += 1;
        state.set((current) => ({
          tags: current.tags?.some((each) => each.id === tag.id)
            ? current.tags
            : [...(current.tags ?? []), tag],
          pending: [...current.pending, tag.id],
          error: undefined,
        }));

        const result = await client.tag(
          organizationId,
          subjectType,
          subjectId,
          tag.id,
        );

        state.set((current) => ({
          pending: without(current.pending, tag.id),
          ...(result.ok
            ? {}
            : {
                error: result.error,
                tags: current.tags?.filter((each) => each.id !== tag.id),
              }),
        }));

        if (!result.ok) {
          return result;
        }

        await changed({ kind: "added", tag, created });

        return ok(tag);
      };

      return {
        actions: {
          refresh,
          add: async (tagId) => {
            const tag = state
              .get()
              .available?.find((each) => each.id === tagId);

            if (!tag) {
              return err(dbError("not_found", "No such tag"));
            }

            return apply(tag, false);
          },
          remove: async (tagId) => {
            if (organizationId === null) {
              return noOrganization();
            }

            const tag = state.get().tags?.find((each) => each.id === tagId);

            if (!tag) {
              return ok(false);
            }

            ticket += 1;
            state.set((current) => ({
              tags: current.tags?.filter((each) => each.id !== tagId),
              pending: [...current.pending, tagId],
              error: undefined,
            }));

            const result = await client.untag(
              organizationId,
              subjectType,
              subjectId,
              tagId,
            );

            state.set((current) => ({
              pending: without(current.pending, tagId),
              ...(result.ok
                ? {}
                : {
                    error: result.error,
                    tags: [...(current.tags ?? []), tag],
                  }),
            }));

            if (result.ok) {
              await changed({ kind: "removed", tag });
            }

            return result;
          },
          create: async (name) => {
            if (organizationId === null) {
              return noOrganization();
            }

            const label = name.trim();

            if (label === "") {
              return err(dbError("invalid_input", "A tag needs a name"));
            }

            const existing = state
              .get()
              .available?.find(
                (each) => each.name.toLowerCase() === label.toLowerCase(),
              );

            if (existing) {
              return apply(existing, false);
            }

            state.set((current) => ({
              pending: [...current.pending, label],
              error: undefined,
            }));
            const made = await client.create(organizationId, kind, label);
            state.set((current) => ({
              pending: without(current.pending, label),
              ...(made.ok
                ? {
                    available: [
                      ...(current.available ?? []),
                      { ...made.data, kind },
                    ],
                  }
                : { error: made.error }),
            }));

            if (!made.ok) {
              return made;
            }

            return apply({ ...made.data, kind }, true);
          },
        },
        start: () =>
          organizationId === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                void refresh();

                return;
              }),
      };
    },
  );
}
