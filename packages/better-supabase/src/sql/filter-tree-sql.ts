/** What a filter tree function needs: its name, its comment and its error. */
export interface FilterTreeFunction {
  /** The function, quoted (`ctx.fn(...)`). */
  readonly fn: string;
  /** The comment above the function, without `-- `. */
  readonly comment: string;
  /** The PL/pgSQL statement that refuses a malformed tree. */
  readonly invalid: string;
}

/**
 * `fn(node jsonb, payload jsonb) returns boolean`: a filter tree (ADR 0046)
 * matched against a JSON document by path. It visits every node, so a call with
 * an empty payload also checks the tree, and it refuses an unknown node or
 * operator.
 */
export function filterTreeSql({
  fn,
  comment,
  invalid,
}: FilterTreeFunction): string {
  return `
${comment
  .split("\n")
  .map((line) => `-- ${line}`)
  .join("\n")}
create or replace function ${fn}(node jsonb, payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_child jsonb;
  v_any boolean := false;
  v_all boolean := true;
  v_result boolean;
  v_op text;
  v_value jsonb;
  v_at jsonb;
  v_text text;
  v_other text;
  v_numeric boolean;
  v_empty boolean;
begin
  if jsonb_typeof(node) is distinct from 'object' then
    ${invalid}
  end if;
  if node ->> 'type' = 'group' then
    if jsonb_typeof(node -> 'rules') is distinct from 'array'
      or coalesce(node ->> 'combinator', 'and') not in ('and', 'or') then
      ${invalid}
    end if;
    for v_child in select e.value from jsonb_array_elements(node -> 'rules') e loop
      v_result := ${fn}(v_child, payload);
      v_any := v_any or v_result;
      v_all := v_all and v_result;
    end loop;
    return case when coalesce(node ->> 'combinator', 'and') = 'or' then v_any else v_all end;
  end if;
  if node ->> 'type' is distinct from 'rule' or jsonb_typeof(node -> 'path') is distinct from 'array' then
    ${invalid}
  end if;
  v_op := coalesce(node ->> 'operator', '');
  v_value := node -> 'value';
  v_at := coalesce(payload, '{}'::jsonb) #> array(select jsonb_array_elements_text(node -> 'path'));
  v_text := v_at #>> '{}';
  v_other := v_value #>> '{}';
  v_numeric := jsonb_typeof(v_value) = 'number' and v_text ~ '^-?[0-9]+(\\.[0-9]+)?$';
  v_empty := v_at is null or v_at = 'null'::jsonb or v_text = '' or v_at = '[]'::jsonb;
  v_result := case
    when v_op = '' then true
    when v_op = 'empty' then v_empty
    when v_op = 'not_empty' then not v_empty
    when v_op in ('is', 'eq') then case when v_numeric then v_text::numeric = v_other::numeric else v_text = v_other end
    when v_op in ('is_not', 'neq') then not coalesce(case when v_numeric then v_text::numeric = v_other::numeric else v_text = v_other end, false)
    when v_op in ('gt', 'is_after') then case when v_numeric then v_text::numeric > v_other::numeric else v_text > v_other end
    when v_op in ('gte', 'is_on_or_after') then case when v_numeric then v_text::numeric >= v_other::numeric else v_text >= v_other end
    when v_op in ('lt', 'is_before') then case when v_numeric then v_text::numeric < v_other::numeric else v_text < v_other end
    when v_op in ('lte', 'is_on_or_before') then case when v_numeric then v_text::numeric <= v_other::numeric else v_text <= v_other end
    when v_op in ('between', 'not_between') then
      jsonb_typeof(v_value) = 'array' and (
        case when jsonb_typeof(v_value -> 0) = 'number' and v_text ~ '^-?[0-9]+(\\.[0-9]+)?$'
          then v_text::numeric between (v_value ->> 0)::numeric and (v_value ->> 1)::numeric
          else v_text between v_value ->> 0 and v_value ->> 1 end
      ) = (v_op = 'between')
    when v_op in ('is_any_of', 'is_none_of') then
      jsonb_typeof(v_value) = 'array'
        and exists (select 1 from jsonb_array_elements_text(v_value) e where e = v_text) = (v_op = 'is_any_of')
    when v_op in ('contains', 'not_contains') then
      (case when jsonb_typeof(v_at) = 'array' then v_at @> jsonb_build_array(v_value)
        else strpos(lower(v_text), lower(v_other)) > 0 end) = (v_op = 'contains')
    when v_op = 'starts_with' then left(lower(v_text), length(v_other)) = lower(v_other)
    when v_op = 'ends_with' then right(lower(v_text), length(v_other)) = lower(v_other)
    when v_op in ('has_any_of', 'has_none_of') then
      jsonb_typeof(v_at) = 'array' and jsonb_typeof(v_value) = 'array'
        and exists (select 1 from jsonb_array_elements(v_value) e where v_at @> jsonb_build_array(e.value)) = (v_op = 'has_any_of')
    when v_op = 'has_all_of' then
      jsonb_typeof(v_at) = 'array' and jsonb_typeof(v_value) = 'array' and v_at @> v_value
  end;
  if v_op not in ('', 'empty', 'not_empty', 'is', 'eq', 'is_not', 'neq', 'gt', 'is_after', 'gte', 'is_on_or_after', 'lt', 'is_before',
    'lte', 'is_on_or_before', 'between', 'not_between', 'is_any_of', 'is_none_of', 'contains', 'not_contains', 'starts_with',
    'ends_with', 'has_any_of', 'has_none_of', 'has_all_of') then
    ${invalid}
  end if;
  v_result := coalesce(v_result, false);
  return case when coalesce((node ->> 'negated')::boolean, false) then not v_result else v_result end;
end;
$$;
revoke execute on function ${fn}(jsonb, jsonb) from public, anon, authenticated;`;
}
