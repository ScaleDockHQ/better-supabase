/**
 * A copy of `@supabase/postgrest-typegen`'s `GeneratorMetadata` contract
 * (version 1), so the published types don't reference the package: it is an
 * optional peer that only the CLI loads. `tests/config/generator-metadata.test-d.ts`
 * checks the copy against the pinned version.
 */

export interface PostgresColumn {
  table_id: number;
  schema: string;
  table: string;
  id: string;
  ordinal_position: number;
  name: string;
  default_value: unknown;
  data_type: string;
  format: string;
  type_schema: string;
  is_identity: boolean;
  identity_generation: "ALWAYS" | "BY DEFAULT" | null;
  is_generated: boolean;
  is_nullable: boolean;
  is_updatable: boolean;
  is_unique: boolean;
  enums: string[];
  check: string | null;
  comment: string | null;
}

export interface PostgresFunctionArg {
  mode: "in" | "inout" | "out" | "table" | "variadic";
  name: string;
  type_id: number;
  has_default: boolean | null;
}

export interface PostgresFunction {
  id: number;
  schema: string;
  name: string;
  language: string;
  definition: string;
  complete_statement: string;
  args: PostgresFunctionArg[];
  argument_types: string;
  identity_argument_types: string;
  return_type_id: number;
  return_type: string;
  return_type_relation_id: number | null;
  is_set_returning_function: boolean;
  prorows: number | null;
  behavior: "IMMUTABLE" | "STABLE" | "VOLATILE";
  security_definer: boolean;
  config_params: { [x: string]: string } | null;
}

/** A reference to a `types` entry by oid; `null` names when it is not in `types`. */
export interface RpcTypeReference {
  type_id: number;
  format: string | null;
  type_schema: string | null;
}

export interface RpcFunctionArg extends RpcTypeReference {
  name: string;
  mode: "in" | "inout" | "variadic";
  has_default: boolean;
  relation_id: number | null;
}

export interface RpcReturnColumn extends RpcTypeReference {
  name: string;
}

export interface RpcFunctionReturns extends RpcTypeReference {
  relation_id: number | null;
  columns: RpcReturnColumn[] | null;
}

export interface RpcFunctionOverload {
  function_id: number;
  args: RpcFunctionArg[];
  returns: RpcFunctionReturns;
  is_set_returning: boolean;
  rows_estimate: number | null;
  setof_options: {
    from: string;
    to: string;
    is_one_to_one: boolean;
    is_setof_return: boolean;
  } | null;
  computed_field_of: number | null;
  error: string | null;
}

/** A function PostgREST exposes under `/rpc`, with its overloads resolved. */
export interface RpcFunction {
  schema: string;
  name: string;
  overloads: RpcFunctionOverload[];
}

export interface GeneratorMetadata {
  version: 1;
  schemas: { id: number; name: string; owner: string }[];
  tables: {
    bytes: number;
    comment: string | null;
    dead_rows_estimate: number;
    id: number;
    live_rows_estimate: number;
    name: string;
    replica_identity: "DEFAULT" | "FULL" | "INDEX" | "NOTHING";
    rls_enabled: boolean;
    rls_forced: boolean;
    schema: string;
    size: string;
  }[];
  foreignTables: {
    comment: string | null;
    id: number;
    name: string;
    schema: string;
  }[];
  views: {
    comment: string | null;
    id: number;
    is_insert_enabled?: boolean | undefined;
    is_updatable: boolean;
    is_update_enabled?: boolean | undefined;
    name: string;
    schema: string;
  }[];
  materializedViews: {
    comment: string | null;
    id: number;
    is_populated: boolean;
    name: string;
    schema: string;
  }[];
  columns: PostgresColumn[];
  primaryKeys: {
    schema: string;
    table_name: string;
    name: string;
    table_id: number;
  }[];
  relationships: {
    foreign_key_name: string;
    schema: string;
    relation: string;
    columns: string[];
    is_one_to_one: boolean;
    referenced_schema: string;
    referenced_relation: string;
    referenced_columns: string[];
  }[];
  functions: PostgresFunction[];
  types: {
    id: number;
    name: string;
    schema: string;
    format: string;
    enums: string[];
    attributes: { name: string; type_id: number }[];
    comment: string | null;
    type_relation_id: number | null;
  }[];
  /**
   * Derived from `functions`; generators resolve it themselves when it is
   * absent, which is how better-supabase stores metadata.
   */
  rpcFunctions?: RpcFunction[] | undefined;
}
