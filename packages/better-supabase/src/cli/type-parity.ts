type Same<A, B> =
  (<G>() => G extends A ? 1 : 2) extends <G>() => G extends B ? 1 : 2
    ? true
    : false;

type Primitive = string | number | boolean | bigint | symbol | null | undefined;

type Plain<T> = T extends Primitive | ((...args: never[]) => unknown)
  ? T
  : T extends readonly (infer E)[]
    ? Plain<E>[]
    : T extends object
      ? { -readonly [K in keyof T]: Plain<Exclude<T[K], undefined>> }
      : T;

type Assignable<A, B> = [Plain<A>] extends [Plain<B>]
  ? [Plain<B>] extends [Plain<A>]
    ? true
    : false
  : false;

type IsUnion<T, U = T> = T extends unknown
  ? [U] extends [T]
    ? false
    : true
  : never;

type OptionalKeys<T> = {
  [K in keyof T]-?: object extends Pick<T, K> ? K : never;
}[keyof T];

type Kind<T> = T extends (...args: never[]) => unknown
  ? "function"
  : T extends readonly unknown[]
    ? "array"
    : T extends object
      ? "object"
      : "leaf";

type Defined<T> = Exclude<T, undefined>;

type Join<P extends string, K> = K extends string
  ? P extends ""
    ? K
    : `${P}.${K}`
  : P;

type ObjectPaths<A, B, P extends string> =
  | {
      [K in Exclude<keyof A, keyof B>]: `${Join<P, K>} (only in the schema)`;
    }[Exclude<keyof A, keyof B>]
  | {
      [K in Exclude<keyof B, keyof A>]: `${Join<P, K>} (only in the type)`;
    }[Exclude<keyof B, keyof A>]
  | (Same<OptionalKeys<A>, OptionalKeys<B>> extends true
      ? never
      : `${P} (optional keys differ)`)
  | {
      [K in keyof A & keyof B]: ParityPaths<
        Defined<A[K]>,
        Defined<B[K]>,
        Join<P, K>
      >;
    }[keyof A & keyof B];

/**
 * The paths where `A` and `B` differ: a key only one of them has, keys optional
 * in only one, or leaves that aren't assignable both ways. Unions are compared
 * as a whole, and functions only by shape.
 */
export type ParityPaths<A, B, P extends string = ""> =
  IsUnion<A> extends true
    ? Assignable<A, B> extends true
      ? never
      : P
    : IsUnion<B> extends true
      ? Assignable<A, B> extends true
        ? never
        : P
      : Kind<A> extends Kind<B>
        ? Kind<A> extends "function"
          ? never
          : Kind<A> extends "array"
            ? A extends readonly (infer EA)[]
              ? B extends readonly (infer EB)[]
                ? ParityPaths<EA, EB, `${P}[]`>
                : P
              : P
            : Kind<A> extends "object"
              ? ObjectPaths<A, B, P>
              : Assignable<A, B> extends true
                ? never
                : P
        : P;
