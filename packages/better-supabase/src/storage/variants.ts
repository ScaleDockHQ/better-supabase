import type { ImageTransform, TransformOptions } from "./bucket.ts";

import { DbException, dbError } from "../core/errors.ts";
import { MAX_SIDE, QUALITY } from "./image-url.ts";

const side = (value: number | undefined): boolean =>
  value === undefined ||
  (Number.isInteger(value) && value >= 1 && value <= MAX_SIDE);

/** Throws for a variant Storage would refuse, when the bucket is defined. */
export function checkVariants(
  bucketId: string,
  variants: Readonly<Record<string, TransformOptions>>,
): void {
  for (const [name, transform] of Object.entries(variants)) {
    if (!side(transform.width) || !side(transform.height)) {
      throw new TypeError(
        `defineBucket("${bucketId}"): variant "${name}" needs a width and height from 1 to ${String(MAX_SIDE)}`,
      );
    }

    if (
      transform.quality !== undefined &&
      (!Number.isInteger(transform.quality) ||
        transform.quality < QUALITY.min ||
        transform.quality > QUALITY.max)
    ) {
      throw new TypeError(
        `defineBucket("${bucketId}"): variant "${name}" needs a quality from ${String(QUALITY.min)} to ${String(QUALITY.max)}`,
      );
    }
  }
}

/**
 * The transform a variant name stands for, or the inline transform. An unknown
 * name throws an `invalid_input` `DbException`, which the bucket methods turn
 * into an error `Result`.
 */
export function transformFor<V extends string>(
  bucketId: string,
  variants: Readonly<Record<V, TransformOptions>>,
  transform: ImageTransform<V> | undefined,
): TransformOptions | undefined {
  if (typeof transform !== "string") {
    return transform;
  }

  const found = Object.hasOwn(variants, transform)
    ? variants[transform]
    : undefined;

  if (!found) {
    throw new DbException(
      dbError(
        "invalid_input",
        `Bucket "${bucketId}" has no image variant "${transform}"`,
        { table: bucketId },
      ),
    );
  }

  return found;
}

/**
 * The transform at `density` times its size, for a `srcset` entry. Width and
 * height scale by the same factor, which stops at Storage's 2500 limit, so a
 * crop keeps its aspect ratio.
 */
export function scaleTransform(
  transform: TransformOptions,
  density: number,
): TransformOptions {
  const sides = [transform.width, transform.height].filter(
    (value) => value !== undefined,
  );

  const factor = Math.min(density, ...sides.map((value) => MAX_SIDE / value));

  const scale = (value: number | undefined) =>
    value === undefined
      ? undefined
      : Math.max(1, Math.min(MAX_SIDE, Math.round(value * factor)));

  const width = scale(transform.width);
  const height = scale(transform.height);

  return {
    ...transform,
    ...(width === undefined ? {} : { width }),
    ...(height === undefined ? {} : { height }),
  };
}
