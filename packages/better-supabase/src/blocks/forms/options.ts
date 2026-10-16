import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.forms.options`. */
export type FormsSqlOptions = {
  readonly subjects?: unknown;
  readonly handlers?: unknown;
  readonly publicLimit?: unknown;
  readonly extraColumns?: unknown;
};

export const formsSqlOptions: BlockOptionsSchema<FormsSqlOptions> =
  blockOptions<FormsSqlOptions>({
    subjects: option.unknown(),
    handlers: option.unknown(),
    publicLimit: option.unknown(),
    extraColumns: option.unknown(),
  });

/** `blocks.signatures.options`. */
export type SignaturesSqlOptions = {
  readonly subjects?: unknown;
};

export const signaturesSqlOptions: BlockOptionsSchema<SignaturesSqlOptions> =
  blockOptions<SignaturesSqlOptions>({
    subjects: option.unknown(),
  });
