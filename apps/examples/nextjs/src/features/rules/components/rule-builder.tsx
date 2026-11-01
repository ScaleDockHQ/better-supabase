// #region recipe:rule-builder
"use client";

import type { DragEndEvent } from "@dnd-kit/core";
import type { RuleField } from "better-supabase/blocks/automations";
import type {
  FilterCombinator,
  FilterGroupNode,
  FilterNode,
  FilterQuery,
  FilterRule,
} from "better-supabase/list";
import type { CSSProperties, ReactNode } from "react";

import {
  closestCenter,
  DndContext,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { contains, ruleOperators } from "better-supabase/blocks/automations";
import { FILTER_OPERATOR_LABELS } from "better-supabase/list";
import {
  GripVerticalIcon,
  ListFilterIcon,
  LockIcon,
  PlusIcon,
  TriangleAlertIcon,
  XIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { createContext, use, useId, useMemo, useState } from "react";
import * as v from "valibot";

import type { RuleBuilderState } from "@/hooks/use-automations";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { useStatusLabel } from "@/features/customers/use-status-label";
import { useRuleBuilder } from "@/hooks/use-automations";
import { useRouter } from "@/i18n/navigation";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  initialConditions,
  LOCKED_CONDITION,
  RULE_SUBJECT,
  RULE_TRIGGER,
} from "../rule-fields";
import { rulesChanged } from "../rules-actions";

const LOCKED = [LOCKED_CONDITION];

/** Groups nest at most this deep, below the `RULE_LIMITS` depth of 6. */
const MAX_GROUP_DEPTH = 3;

interface Editor {
  readonly builder: RuleBuilderState;
  readonly fields: ReadonlyMap<string, RuleField>;
  /** The first problem the check found on each node, by node id. */
  readonly issues: ReadonlyMap<string, string>;
  readonly readOnly: boolean;
}

const EditorContext = createContext<Editor | null>(null);

function useEditor(): Editor {
  const editor = use(EditorContext);

  if (!editor) {
    throw new Error("Render rule editor parts inside <RuleBuilder>");
  }

  return editor;
}

/** The node an issue path such as `["filter", "rules", 1, "value"]` names. */
function nodeAt(
  tree: FilterQuery,
  path: readonly PropertyKey[] | undefined,
): string {
  let node: FilterNode = tree;

  for (let index = 1; index < (path?.length ?? 0); index += 1) {
    const position = path?.[index + 1];

    if (
      path?.[index] !== "rules" ||
      node.type !== "group" ||
      !Number.isInteger(position)
    ) {
      break;
    }

    const child: FilterNode | undefined = node.rules[Number(position)];

    if (child === undefined) {
      break;
    }

    node = child;
    index += 1;
  }

  return node.id;
}

/**
 * The "When" editor of one customer rule: conditions on the catalog fields in
 * nested And/Or groups, reordered by their handles, with the first condition
 * locked. Saves through the browser client as the signed-in user.
 */
export function RuleBuilder({
  organizationId,
  rule,
  canEdit,
  canPublish,
}: {
  organizationId: string;
  /** The rule to edit; `null` starts a new one. */
  rule: string | null;
  canEdit: boolean;
  canPublish: boolean;
}) {
  const t = useExtracted("rules");
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const nameId = useId();
  const enabledId = useId();
  const [enabledEdit, setEnabledEdit] = useState<boolean | undefined>();

  const builder = useRuleBuilder({
    organizationId,
    rule,
    subjectType: RULE_SUBJECT,
    trigger: RULE_TRIGGER,
    initial: initialConditions,
    locked: LOCKED,
    schema: blockConfig.automations.api,
  });

  const enabled = enabledEdit ?? builder.rule?.enabled ?? false;

  const fields = useMemo(
    () => new Map((builder.fields ?? []).map((field) => [field.id, field])),
    [builder.fields],
  );

  const issues = useMemo(() => {
    const byNode = new Map<string, string>();

    for (const issue of builder.issues) {
      const id = nodeAt(builder.conditions, issue.path);

      if (!byNode.has(id)) {
        byNode.set(id, issue.message);
      }
    }

    return byNode;
  }, [builder.issues, builder.conditions]);

  const editor = useMemo(
    () => ({ builder, fields, issues, readOnly: !canEdit }),
    [builder, fields, issues, canEdit],
  );

  if (builder.fields === undefined) {
    return builder.error ? (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The rule didn't load")}</AlertTitle>
        <AlertDescription>{errorMessage(builder.error)}</AlertDescription>
        <AlertAction>
          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={() => {
              void builder.refresh();
            }}
          >
            {t("Retry")}
          </Button>
        </AlertAction>
      </Alert>
    ) : (
      <RuleBuilderSkeleton />
    );
  }

  const enabledChanged =
    enabledEdit !== undefined && enabledEdit !== builder.rule?.enabled;

  const save = async () => {
    const saved = await builder.save(
      enabledChanged ? { enabled: enabledEdit } : {},
    );

    if (saved === undefined) {
      return;
    }

    setEnabledEdit(undefined);
    await rulesChanged({});

    if (rule === null) {
      router.replace(`/rules/${saved.id}`);
    }
  };

  return (
    <EditorContext value={editor}>
      <Card data-recipe="rule-builder">
        <CardHeader>
          <CardTitle>{t("When a lead is saved")}</CardTitle>
          <CardDescription>
            {t(
              "The rule matches when its conditions hold for the saved customer.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-6">
          <Field>
            <FieldLabel htmlFor={nameId}>{t("Name")}</FieldLabel>
            <Input
              id={nameId}
              value={builder.name}
              maxLength={200}
              disabled={!canEdit}
              placeholder={t("Follow up on large leads")}
              onChange={(event) => {
                builder.setName(event.target.value);
              }}
            />
          </Field>
          {builder.conditions.rules.length === 0 ? (
            <EmptyConditions />
          ) : (
            <GroupEditor group={builder.conditions} depth={1} />
          )}
          {builder.error ? (
            <Alert variant="destructive" aria-live="polite">
              <TriangleAlertIcon />
              <AlertTitle>{t("The rule wasn't saved")}</AlertTitle>
              <AlertDescription>{errorMessage(builder.error)}</AlertDescription>
            </Alert>
          ) : null}
        </CardContent>
        {canEdit ? (
          <CardFooter className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <Switch
                id={enabledId}
                checked={enabled}
                disabled={!canPublish || builder.saving}
                onCheckedChange={setEnabledEdit}
              />
              <Label htmlFor={enabledId} className="text-sm font-normal">
                {canPublish
                  ? t("Enabled")
                  : t("Enabled (needs publish rights)")}
              </Label>
            </div>
            <div className="flex items-center gap-2">
              <Button
                type="button"
                size="sm"
                variant="outline"
                disabled={(!builder.dirty && !enabledChanged) || builder.saving}
                onClick={() => {
                  builder.reset();
                  setEnabledEdit(undefined);
                }}
              >
                {t("Discard")}
              </Button>
              <Button
                type="button"
                size="sm"
                data-testid="save-rule"
                disabled={
                  builder.saving ||
                  builder.name.trim() === "" ||
                  builder.issues.length > 0 ||
                  (!builder.dirty && !enabledChanged)
                }
                onClick={() => {
                  void save();
                }}
              >
                {builder.saving ? t("Saving") : t("Save rule")}
              </Button>
            </div>
          </CardFooter>
        ) : null}
      </Card>
    </EditorContext>
  );
}

function EmptyConditions() {
  const t = useExtracted("rules");
  const { builder, readOnly } = useEditor();

  return (
    <Empty className="border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <ListFilterIcon />
        </EmptyMedia>
        <EmptyTitle>{t("No conditions")}</EmptyTitle>
        <EmptyDescription>
          {t("Without conditions the rule matches every saved customer.")}
        </EmptyDescription>
      </EmptyHeader>
      {readOnly ? null : (
        <EmptyContent>
          <Button
            type="button"
            size="sm"
            onClick={() => {
              builder.addRule({ field: builder.fields?.[0]?.id });
            }}
          >
            <PlusIcon />
            {t("Add condition")}
          </Button>
        </EmptyContent>
      )}
    </Empty>
  );
}

function GroupEditor({
  group,
  depth,
}: {
  group: FilterGroupNode;
  depth: number;
}) {
  const t = useExtracted("rules");
  const { builder, readOnly } = useEditor();
  const locked = new Set(builder.locked);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  const onDragEnd = ({ active, over }: DragEndEvent) => {
    if (!over || active.id === over.id || locked.has(String(over.id))) {
      return;
    }

    const index = group.rules.findIndex((child) => child.id === over.id);

    if (index !== -1) {
      builder.move({ id: String(active.id), group: group.id, index });
    }
  };

  return (
    <div className="flex flex-col gap-3">
      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        onDragEnd={onDragEnd}
      >
        <SortableContext
          items={group.rules.map((child) => child.id)}
          strategy={verticalListSortingStrategy}
        >
          <ol className="flex flex-col gap-2">
            {group.rules.map((child, index) => (
              <SortableNode
                key={child.id}
                node={child}
                disabled={readOnly || locked.has(child.id)}
              >
                <Connective group={group} index={index} />
                {child.type === "rule" ? (
                  <ConditionRow rule={child} />
                ) : (
                  <NestedGroup group={child} depth={depth + 1} />
                )}
              </SortableNode>
            ))}
          </ol>
        </SortableContext>
      </DndContext>
      {readOnly ? null : (
        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            size="sm"
            variant="ghost"
            onClick={() => {
              builder.addRule({
                group: group.id,
                field: builder.fields?.[0]?.id,
              });
            }}
          >
            <PlusIcon />
            {t("Add condition")}
          </Button>
          {depth < MAX_GROUP_DEPTH ? (
            <Button
              type="button"
              size="sm"
              variant="ghost"
              onClick={() => {
                const added = builder.addGroup({
                  group: group.id,
                  combinator: group.combinator === "and" ? "or" : "and",
                });

                builder.addRule({
                  group: added,
                  field: builder.fields?.[0]?.id,
                });
              }}
            >
              <PlusIcon />
              {t("Add group")}
            </Button>
          ) : null}
        </div>
      )}
    </div>
  );
}

function SortableNode({
  node,
  disabled,
  children,
}: {
  node: FilterNode;
  disabled: boolean;
  children: ReactNode;
}) {
  const t = useExtracted("rules");
  const { builder } = useEditor();
  const locked = builder.locked.includes(node.id);

  const {
    attributes,
    listeners,
    setNodeRef,
    setActivatorNodeRef,
    transform,
    isDragging,
  } = useSortable({ id: node.id, disabled });

  // SAFETY: React's CSSProperties has no custom properties; it is a CSS transform.
  const style = {
    "--drag-transform": CSS.Transform.toString(transform) ?? "none",
  } as CSSProperties;

  return (
    <li
      ref={setNodeRef}
      style={style}
      data-dragging={isDragging || undefined}
      className="flex [transform:var(--drag-transform)] items-start gap-2 transition-transform duration-200 data-dragging:opacity-60 data-dragging:transition-none motion-reduce:transition-none"
    >
      {locked ? (
        <span
          className="flex size-8 shrink-0 items-center justify-center text-muted-foreground"
          title={t("This condition is fixed")}
        >
          <LockIcon className="size-4" aria-hidden />
          <span className="sr-only">{t("This condition is fixed")}</span>
        </span>
      ) : (
        <Button
          ref={setActivatorNodeRef}
          type="button"
          size="icon-sm"
          variant="ghost"
          disabled={disabled}
          aria-label={t("Reorder")}
          className="cursor-grab"
          {...attributes}
          {...listeners}
        >
          <GripVerticalIcon />
        </Button>
      )}
      {children}
    </li>
  );
}

/** "Where" before the first child; the group's And or Or before the rest. */
function Connective({
  group,
  index,
}: {
  group: FilterGroupNode;
  index: number;
}) {
  const t = useExtracted("rules");
  const { builder, readOnly } = useEditor();

  const label = (combinator: FilterCombinator) =>
    combinator === "and" ? t("And") : t("Or");

  if (index === 0) {
    return (
      <span className="flex h-8 w-20 shrink-0 items-center text-sm text-muted-foreground">
        {t("Where")}
      </span>
    );
  }

  if (index > 1 || readOnly) {
    return (
      <span className="flex h-8 w-20 shrink-0 items-center text-sm text-muted-foreground">
        {label(group.combinator)}
      </span>
    );
  }

  return (
    <Select
      value={group.combinator}
      items={[
        { value: "and", label: label("and") },
        { value: "or", label: label("or") },
      ]}
      onValueChange={(value) => {
        if (value === "and" || value === "or") {
          builder.setCombinator({ group: group.id, combinator: value });
        }
      }}
    >
      <SelectTrigger size="sm" className="w-20" aria-label={t("Combine with")}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="and">{label("and")}</SelectItem>
        <SelectItem value="or">{label("or")}</SelectItem>
      </SelectContent>
    </Select>
  );
}

function NestedGroup({
  group,
  depth,
}: {
  group: FilterGroupNode;
  depth: number;
}) {
  const t = useExtracted("rules");
  const { builder, readOnly } = useEditor();

  const removable =
    !readOnly && !builder.locked.some((id) => contains(group, id));

  return (
    <div className="flex min-w-0 flex-1 items-start gap-2 border-l-2 pl-3">
      <div className="min-w-0 flex-1">
        <GroupEditor group={group} depth={depth} />
      </div>
      {removable ? (
        <Button
          type="button"
          size="icon-sm"
          variant="ghost"
          aria-label={t("Remove group")}
          onClick={() => {
            builder.remove(group.id);
          }}
        >
          <XIcon />
        </Button>
      ) : null}
    </div>
  );
}

function useFieldLabel(): (field: RuleField) => string {
  const t = useExtracted("rules");

  return (field) => {
    switch (field.id) {
      case "status": {
        return t("Status");
      }

      case "name": {
        return t("Name");
      }

      case "kvk": {
        return t("KvK number");
      }

      case "createdAt": {
        return t("Created");
      }

      default: {
        return field.label;
      }
    }
  };
}

function useOperatorLabel(): (operator: string) => string {
  const t = useExtracted("rules");

  return (operator) => {
    switch (operator) {
      case "is": {
        return t("is");
      }

      case "is_not": {
        return t("is not");
      }

      case "contains": {
        return t("contains");
      }

      case "not_contains": {
        return t("does not contain");
      }

      case "starts_with": {
        return t("starts with");
      }

      case "empty": {
        return t("is empty");
      }

      case "not_empty": {
        return t("is not empty");
      }

      case "is_before": {
        return t("is before");
      }

      case "is_after": {
        return t("is after");
      }

      default: {
        return FILTER_OPERATOR_LABELS[operator] ?? operator;
      }
    }
  };
}

function ConditionRow({ rule }: { rule: FilterRule }) {
  const t = useExtracted("rules");
  const { builder, fields, issues, readOnly } = useEditor();
  const fieldLabel = useFieldLabel();
  const operatorLabel = useOperatorLabel();
  const field = fields.get(rule.path.join("."));
  const operators = field ? ruleOperators(field) : [];
  const spec = operators.find((entry) => entry.value === rule.operator);
  const disabled = readOnly || builder.locked.includes(rule.id);
  const issue = issues.get(rule.id);

  return (
    <div className="flex min-w-0 flex-1 flex-col gap-1">
      <div className="flex min-w-0 flex-wrap items-center gap-2">
        <Select
          value={field?.id ?? null}
          disabled={disabled}
          items={(builder.fields ?? []).map((entry) => ({
            value: entry.id,
            label: fieldLabel(entry),
          }))}
          onValueChange={(value) => {
            if (value !== null) {
              builder.setField({ id: rule.id, field: value });
            }
          }}
        >
          <SelectTrigger size="sm" className="w-40" aria-label={t("Field")}>
            <SelectValue placeholder={t("Field")} />
          </SelectTrigger>
          <SelectContent>
            {(builder.fields ?? []).map((entry) => (
              <SelectItem key={entry.id} value={entry.id}>
                {fieldLabel(entry)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select
          value={spec?.value ?? null}
          disabled={disabled || field === undefined}
          items={operators.map((entry) => ({
            value: entry.value,
            label: operatorLabel(entry.value),
          }))}
          onValueChange={(value) => {
            if (value !== null) {
              builder.setOperator({ id: rule.id, operator: value });
            }
          }}
        >
          <SelectTrigger size="sm" className="w-40" aria-label={t("Operator")}>
            <SelectValue placeholder={t("Operator")} />
          </SelectTrigger>
          <SelectContent>
            {operators.map((entry) => (
              <SelectItem key={entry.value} value={entry.value}>
                {operatorLabel(entry.value)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {field && spec?.arity === "one" ? (
          <ValueControl
            field={field}
            value={valueText(field, rule)}
            disabled={disabled}
            onChange={(text) => {
              builder.setValue({ id: rule.id, value: valueOf(field, text) });
            }}
          />
        ) : null}
        {disabled ? null : (
          <Button
            type="button"
            size="icon-sm"
            variant="ghost"
            aria-label={t("Remove condition")}
            onClick={() => {
              builder.remove(rule.id);
            }}
          >
            <XIcon />
          </Button>
        )}
      </div>
      {issue ? <FieldError>{issue}</FieldError> : null}
    </div>
  );
}

const Text = v.fallback(v.string(), "");

const NumberText = v.fallback(
  v.pipe(v.number(), v.finite(), v.transform(String)),
  "",
);

const BooleanText = v.fallback(
  v.pipe(
    v.union([v.boolean(), v.picklist(["true", "false"])]),
    v.transform(String),
  ),
  "",
);

const DayText = v.fallback(
  v.pipe(
    v.object({ date: v.string() }),
    v.transform((value) => value.date),
  ),
  "",
);

/** A condition's value as the text its control shows; `""` when unset. */
function valueText(field: RuleField, rule: FilterRule): string {
  switch (field.type) {
    case "number": {
      return v.parse(NumberText, rule.value);
    }

    case "date": {
      return v.parse(DayText, rule.value);
    }

    case "boolean": {
      return v.parse(BooleanText, rule.value);
    }

    case "text":
    case "select":
    case "multiselect":
    case "relation": {
      return v.parse(Text, rule.value);
    }

    default: {
      const never: never = field.type;

      return String(never);
    }
  }
}

/** The value a control's text stands for; `undefined` clears it. */
function valueOf(field: RuleField, text: string): FilterRule["value"] {
  if (text === "" && field.type !== "text") {
    return undefined;
  }

  switch (field.type) {
    case "number": {
      return Number(text);
    }

    case "date": {
      return { date: text };
    }

    case "text":
    case "boolean":
    case "select":
    case "multiselect":
    case "relation": {
      return text;
    }

    default: {
      const never: never = field.type;

      return String(never);
    }
  }
}

/** One value for the field's type: text, a number, a day or an option. */
function ValueControl({
  field,
  value,
  disabled,
  onChange,
}: {
  field: RuleField;
  value: string;
  disabled: boolean;
  onChange: (text: string) => void;
}) {
  const t = useExtracted("rules");
  const statusLabel = useStatusLabel();

  switch (field.type) {
    case "select":
    case "multiselect":
    case "relation":
    case "boolean": {
      const options =
        field.type === "boolean"
          ? [
              { value: "true", label: t("Yes") },
              { value: "false", label: t("No") },
            ]
          : (field.options ?? []).map((option) => ({
              value: option.value,
              label:
                field.id === "status"
                  ? statusLabel(option.value)
                  : option.label,
            }));

      return (
        <Select
          value={value === "" ? null : value}
          disabled={disabled}
          items={options}
          onValueChange={(next) => {
            if (next !== null) {
              onChange(next);
            }
          }}
        >
          <SelectTrigger size="sm" className="w-40" aria-label={t("Value")}>
            <SelectValue placeholder={t("Value")} />
          </SelectTrigger>
          <SelectContent>
            {options.map((option) => (
              <SelectItem key={option.value} value={option.value}>
                {option.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      );
    }

    case "number":
    case "date":
    case "text": {
      return (
        <Input
          type={field.type}
          className={field.type === "text" ? "w-48" : "w-40"}
          aria-label={t("Value")}
          disabled={disabled}
          value={value}
          onChange={(event) => {
            onChange(event.target.value);
          }}
        />
      );
    }

    default: {
      const never: never = field.type;

      return String(never);
    }
  }
}

export function RuleBuilderSkeleton() {
  return (
    <Card aria-busy="true">
      <CardHeader>
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-4 w-72" />
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        <Skeleton className="h-9 w-full" />
        <div className="flex flex-col gap-2">
          {[0, 1, 2].map((row) => (
            <Skeleton key={row} className="h-8 w-full" />
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
// #endregion recipe:rule-builder
