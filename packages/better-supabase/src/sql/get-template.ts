export interface GetTemplateOptions {
  /** The function name as it is created, such as the output of `fn("get_till")`. */
  readonly name: string;
  /** The bare function name, for the qualified argument. */
  readonly bare: string;
  /** The name of the uuid argument. */
  readonly arg: string;
  /** The table expression, aliased as `x`. */
  readonly from: string;
  readonly idColumn: string;
  readonly tenantColumn: string;
  /** The SQL type of the tenant column. */
  readonly tenantType: string;
  /** The JSON of one row, over `x`. */
  readonly rowJson: string;
  /** The condition that holds when the caller may read `v_tenant`. */
  readonly allowed: (tenant: string) => string;
  /** The raise statement for a caller who may not read the row. */
  readonly forbidden: string;
  /** The grant statement for the function. */
  readonly grant: string;
}

/**
 * A `get_<entity>` function of the block list contract (ADR 1077): the one row
 * with the given id as JSON, or null when there is none. A row of another
 * organization the caller can't read raises the block's forbidden error, the
 * same as the list functions do.
 */
export function getFunction(options: GetTemplateOptions): string {
  const { bare, arg } = options;

  return `create or replace function ${options.name}(${arg} uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${options.tenantType};
  v_row jsonb;
begin
  select x.${options.tenantColumn}, ${options.rowJson}
    into v_tenant, v_row
    from ${options.from} x
    where x.${options.idColumn} = ${bare}.${arg};
  if v_row is null then
    return null;
  end if;
  if not ${options.allowed("v_tenant")} then
    ${options.forbidden}
  end if;
  return v_row;
end;
$$;
${options.grant}
`;
}
