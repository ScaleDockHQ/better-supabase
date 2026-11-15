import type {
  ChannelProduct,
  LocalizedProduct,
  Price,
  ProductMedia,
} from "./catalog.ts";

import { money } from "../../commerce/money.ts";
import { optionalMoneyOf } from "../money-codec.ts";
import {
  enumOrThrow,
  instantOf,
  isRecord,
  optionalText,
  recordsOf,
  textOf,
} from "../shared.ts";

export const PRODUCT_KINDS = ["physical", "digital", "service"] as const;

export function priceOf(value: unknown): Price | null {
  if (!isRecord(value)) {
    return null;
  }

  const currency = textOf(value["currency"]);
  const compareAt = optionalMoneyOf(value["compareAt"], currency);
  const priceListId = optionalText(value["priceListId"]);

  return {
    id: textOf(value["id"]),
    variantId: textOf(value["variantId"]),
    amount: money(BigInt(textOf(value["amount"])), currency),
    ...(compareAt === undefined ? {} : { compareAt }),
    ...(priceListId === undefined ? {} : { priceListId }),
  };
}

export function countOf(value: unknown): number {
  const count = typeof value === "number" ? value : Number(textOf(value));

  if (!Number.isInteger(count)) {
    throw new TypeError(
      `set_channel_listing returned ${JSON.stringify(value)}`,
    );
  }

  return count;
}

function textsOf(value: unknown): Readonly<Record<string, string>> {
  if (!isRecord(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).flatMap(([key, entry]) =>
      typeof entry === "string" ? [[key, entry]] : [],
    ),
  );
}

export function channelProductOf(row: Record<string, unknown>): ChannelProduct {
  const description = optionalText(row["description"]);

  const kind =
    row["kind"] === null || row["kind"] === undefined
      ? undefined
      : enumOrThrow(row["kind"], PRODUCT_KINDS, "product kind");

  return {
    id: textOf(row["id"]),
    slug: textOf(row["slug"]),
    status: textOf(row["status"]),
    ...(kind === undefined ? {} : { kind }),
    locale: textOf(row["locale"]),
    title: textOf(row["title"]),
    ...(description === undefined ? {} : { description }),
    listedAt: instantOf(row["listedAt"]),
  };
}

export function localizedOf(value: unknown): LocalizedProduct | null {
  if (!isRecord(value)) {
    return null;
  }

  const description = optionalText(value["description"]);

  return {
    id: textOf(value["id"]),
    slug: textOf(value["slug"]),
    locale: textOf(value["locale"]),
    title: textOf(value["title"]),
    ...(description === undefined ? {} : { description }),
    variants: recordsOf(value["variants"], "product_text").map((entry) => {
      const title = optionalText(entry["title"]);

      return {
        id: textOf(entry["id"]),
        sku: textOf(entry["sku"]),
        ...(title === undefined ? {} : { title }),
      };
    }),
  };
}

export function mediaOf(row: Record<string, unknown>): ProductMedia {
  const variantId = optionalText(row["variantId"]);
  const alt = optionalText(row["alt"]);

  return {
    id: textOf(row["id"]),
    attachmentId: textOf(row["attachmentId"]),
    ...(variantId === undefined ? {} : { variantId }),
    position: Number(row["position"]),
    ...(alt === undefined ? {} : { alt }),
    altByLocale: textsOf(row["altByLocale"]),
  };
}
