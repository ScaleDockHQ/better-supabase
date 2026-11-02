import type { DbError, ValidationIssue } from "../../core/errors.ts";
import type {
  FilterCombinator,
  FilterLimits,
  FilterNode,
  FilterQuery,
  FilterRule,
} from "../../list/filter-query.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Rule, RuleAction, Automations } from "./automations.ts";
import type { RuleField } from "./fields.ts";

import { defineController, whileSignedIn } from "../controller.ts";
import { checkRuleConditions, RULE_LIMITS } from "./fields.ts";
import {
  emptyConditions,
  findNode,
  insertNode,
  moveNode,
  removeNode,
  ruleOperators,
  setCombinator,
  setRuleField,
  setRuleOperator,
  updateNode,
} from "./tree.ts";

export interface RuleBuilderControllerOptions {
  readonly client: Pick<Automations, "fields" | "get" | "upsert">;
  readonly auth: AuthPort;
  readonly organizationId: string;
  /** The rule to edit; `null` edits a new one. */
  readonly rule: string | null;
  /** The record type whose fields the rules test. */
  readonly subjectType: string;
  /** A new rule's trigger, such as `expense.submitted`. */
  readonly trigger?: string;
  /** The tree a new rule starts with, such as a fixed first condition. */
  readonly initial?: FilterQuery;
  /**
   * Node ids the editor may not change, move or remove, such as the fixed first
   * condition. Only the editor knows them; the stored rule doesn't.
   */
  readonly locked?: readonly string[];
  /** Defaults to `RULE_LIMITS`. */
  readonly limits?: FilterLimits;
  /** Makes node ids. Defaults to `crypto.randomUUID()`. */
  readonly newId?: () => string;
}

export interface RuleBuilderSnapshot {
  /** The stored rule; `undefined` for a new one or before the first load. */
  readonly rule: Rule | undefined;
  /** The subject type's field catalog; `undefined` until loaded. */
  readonly fields: readonly RuleField[] | undefined;
  readonly name: string;
  readonly conditions: FilterQuery;
  readonly actions: readonly RuleAction[];
  readonly stopProcessing: boolean;
  readonly locked: readonly string[];
  /** Problems in the tree, checked against the fields once they load. */
  readonly issues: readonly ValidationIssue[];
  /**
   * Whether the name, tree, actions or `stopProcessing` differ from the stored
   * rule.
   */
  readonly dirty: boolean;
  readonly loading: boolean;
  readonly saving: boolean;
  readonly error: DbError | undefined;
}

export interface RuleBuilderActions {
  /** Loads the fields and the rule again, dropping unsaved edits. */
  readonly refresh: () => Promise<void>;
  /** Adds a condition to `group` (the root by default) and returns its id. */
  readonly addRule: (input?: {
    group?: string | undefined;
    field?: string | undefined;
  }) => string;
  /** Adds an empty group to `group` (the root by default) and returns its id. */
  readonly addGroup: (input?: {
    group?: string | undefined;
    combinator?: FilterCombinator | undefined;
  }) => string;
  readonly remove: (id: string) => void;
  /** Moves a node into `group`, where it ends up at `index`. */
  readonly move: (input: { id: string; group: string; index: number }) => void;
  readonly setField: (input: { id: string; field: string }) => void;
  /** Keeps the value when the operator takes the same kind of value. */
  readonly setOperator: (input: { id: string; operator: string }) => void;
  readonly setValue: (input: { id: string; value: unknown }) => void;
  readonly setNegated: (input: { id: string; negated: boolean }) => void;
  readonly setCombinator: (input: {
    group: string;
    combinator: FilterCombinator;
  }) => void;
  readonly setName: (name: string) => void;
  readonly setActions: (actions: readonly RuleAction[]) => void;
  readonly setStopProcessing: (stop: boolean) => void;
  readonly lock: (id: string) => void;
  readonly unlock: (id: string) => void;
  /** Drops unsaved edits. */
  readonly reset: () => void;
  /**
   * Saves the rule, `enabled` turning it on or off with it. The saved rule, or
   * `undefined` with `error` set.
   */
  readonly save: (options?: {
    readonly enabled?: boolean;
  }) => Promise<Rule | undefined>;
}

export type RuleBuilderController = Controller<
  RuleBuilderSnapshot,
  RuleBuilderActions
>;

interface Draft {
  readonly name: string;
  readonly conditions: FilterQuery;
  readonly actions: readonly RuleAction[];
  readonly stopProcessing: boolean;
}

const draftOf = (snapshot: Draft): string =>
  JSON.stringify([
    snapshot.name,
    snapshot.conditions,
    snapshot.actions,
    snapshot.stopProcessing,
  ]);

const fieldById = (
  fields: readonly RuleField[] | undefined,
  id: string,
): RuleField | undefined => fields?.find((field) => field.id === id);

/**
 * The editor state of one rule: the field catalog, the condition tree and the
 * edits to it, with validation, dirty state and save.
 */
export function createRuleBuilderController(
  options: RuleBuilderControllerOptions,
): RuleBuilderController {
  const { client, organizationId } = options;
  const limits = options.limits ?? RULE_LIMITS;
  const newId = options.newId ?? (() => crypto.randomUUID());

  const blank: Draft = {
    name: "",
    conditions: options.initial ?? emptyConditions(),
    actions: [],
    stopProcessing: false,
  };

  return defineController<RuleBuilderSnapshot, RuleBuilderActions>(
    {
      rule: undefined,
      fields: undefined,
      ...blank,
      locked: options.locked ?? [],
      issues: [],
      dirty: false,
      loading: true,
      saving: false,
      error: undefined,
    },
    (state) => {
      let baseline = draftOf(blank);

      const issuesOf = (
        conditions: FilterQuery,
        fields: readonly RuleField[] | undefined,
      ): readonly ValidationIssue[] =>
        fields === undefined
          ? []
          : checkRuleConditions(conditions, fields, limits);

      const edit = (patch: Partial<Draft>): void => {
        state.set((current) => {
          const next = { ...current, ...patch };

          return {
            ...patch,
            issues: issuesOf(next.conditions, current.fields),
            dirty: draftOf(next) !== baseline,
          };
        });
      };

      const isLocked = (id: string): boolean => state.get().locked.includes(id);

      /** Locked nodes, and groups that hold one, stay where they are. */
      const holdsLocked = (id: string): boolean => {
        const node = findNode(state.get().conditions, id);

        return (
          node !== undefined &&
          state
            .get()
            .locked.some((locked) => findNode(node, locked) !== undefined)
        );
      };

      const editTree = (
        id: string,
        change: (tree: FilterQuery) => FilterQuery,
      ): void => {
        if (isLocked(id)) {
          return;
        }

        edit({ conditions: change(state.get().conditions) });
      };

      const editRule = (
        id: string,
        change: (
          rule: FilterRule,
          fields: readonly RuleField[] | undefined,
        ) => FilterNode,
      ): void => {
        editTree(id, (tree) =>
          updateNode(tree, id, (node) =>
            node.type === "rule" ? change(node, state.get().fields) : node,
          ),
        );
      };

      const restore = (rule: Rule | undefined): void => {
        const draft: Draft =
          rule === undefined
            ? blank
            : {
                name: rule.name,
                conditions: rule.conditions,
                actions: rule.actions,
                stopProcessing: rule.stopProcessing,
              };

        baseline = draftOf(draft);
        state.set((current) => ({
          rule,
          ...draft,
          issues: issuesOf(draft.conditions, current.fields),
          dirty: false,
        }));
      };

      const refresh = async (): Promise<void> => {
        const run = state.run();
        state.set({ loading: true });

        const [fields, rule] = await Promise.all([
          client.fields(options.subjectType),
          options.rule === null
            ? Promise.resolve(undefined)
            : client.get(options.rule),
        ]);

        if (run !== state.run()) {
          return;
        }

        const failure = rule?.ok === false ? rule.error : undefined;

        state.set({
          loading: false,
          error: fields.ok ? failure : fields.error,
          ...(fields.ok ? { fields: fields.data } : {}),
        });

        if (rule === undefined || rule.ok) {
          restore(rule?.data);
        }
      };

      const addRule = ({
        group,
        field,
      }: {
        group?: string | undefined;
        field?: string | undefined;
      } = {}): string => {
        const id = newId();
        const target = group ?? state.get().conditions.id;

        const chosen =
          field === undefined
            ? undefined
            : fieldById(state.get().fields, field);

        const operator =
          chosen === undefined ? "" : (ruleOperators(chosen)[0]?.value ?? "");

        edit({
          conditions: insertNode(state.get().conditions, target, {
            id,
            type: "rule",
            path: chosen === undefined ? [] : chosen.id.split("."),
            operator,
          }),
        });

        return id;
      };

      const addGroup = ({
        group,
        combinator = "and",
      }: {
        group?: string | undefined;
        combinator?: FilterCombinator | undefined;
      } = {}): string => {
        const id = newId();
        const target = group ?? state.get().conditions.id;

        edit({
          conditions: insertNode(state.get().conditions, target, {
            id,
            type: "group",
            combinator,
            rules: [],
          }),
        });

        return id;
      };

      const save = async (
        saveOptions: { readonly enabled?: boolean } = {},
      ): Promise<Rule | undefined> => {
        const current = state.get();
        const run = state.run();
        state.set({ saving: true, error: undefined });

        const saved = await client.upsert({
          organizationId,
          input: {
            ...(current.rule === undefined
              ? {
                  subjectType: options.subjectType,
                  ...(options.trigger === undefined
                    ? {}
                    : { trigger: options.trigger }),
                }
              : { id: current.rule.id, version: current.rule.version }),
            name: current.name,
            conditions: current.conditions,
            actions: current.actions,
            stopProcessing: current.stopProcessing,
            ...(saveOptions.enabled === undefined
              ? {}
              : { enabled: saveOptions.enabled }),
          },
        });

        if (run !== state.run()) {
          return saved.ok ? saved.data : undefined;
        }

        state.set({ saving: false });

        if (!saved.ok) {
          state.set({ error: saved.error });

          return undefined;
        }

        restore(saved.data);

        return saved.data;
      };

      return {
        actions: {
          refresh,
          addRule,
          addGroup,
          remove: (id) => {
            if (!holdsLocked(id)) {
              edit({ conditions: removeNode(state.get().conditions, id) });
            }
          },
          move: ({ id, group, index }) => {
            if (!holdsLocked(id)) {
              edit({
                conditions: moveNode(state.get().conditions, id, group, index),
              });
            }
          },
          setField: ({ id, field }) => {
            editRule(id, (rule, fields) => {
              const next = fieldById(fields, field);

              return next === undefined
                ? rule
                : setRuleField(
                    rule,
                    next,
                    fieldById(fields, rule.path.join(".")),
                  );
            });
          },
          setOperator: ({ id, operator }) => {
            editRule(id, (rule, fields) =>
              setRuleOperator(
                rule,
                operator,
                fieldById(fields, rule.path.join(".")),
              ),
            );
          },
          setValue: ({ id, value }) => {
            editRule(id, (rule) => ({ ...rule, value }));
          },
          setNegated: ({ id, negated }) => {
            editRule(id, (rule) => ({ ...rule, negated }));
          },
          setCombinator: ({ group, combinator }) => {
            editTree(group, (tree) => setCombinator(tree, group, combinator));
          },
          setName: (name) => {
            edit({ name });
          },
          setActions: (actions) => {
            edit({ actions });
          },
          setStopProcessing: (stopProcessing) => {
            edit({ stopProcessing });
          },
          lock: (id) => {
            if (!isLocked(id)) {
              state.set({ locked: [...state.get().locked, id] });
            }
          },
          unlock: (id) => {
            state.set({
              locked: state.get().locked.filter((locked) => locked !== id),
            });
          },
          reset: () => {
            restore(state.get().rule);
          },
          save,
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();

            return;
          }),
      };
    },
  );
}
