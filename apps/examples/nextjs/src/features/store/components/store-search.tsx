"use client";

import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import {
  debounce,
  parseAsBoolean,
  parseAsString,
  parseAsStringLiteral,
  useQueryStates,
} from "nuqs";

import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldLabel } from "@/components/ui/field";
import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
} from "@/components/ui/input-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import { STORE_SORTS } from "../store-sorts";

const parsers = {
  q: parseAsString.withDefault(""),
  sort: parseAsStringLiteral(STORE_SORTS).withDefault("newest"),
  stock: parseAsBoolean.withDefault(false),
};

/**
 * Search, sort and the in-stock filter of the catalog. Every control writes the
 * URL and the server renders the matching products (`shallow: false`).
 */
export function StoreSearch() {
  const t = useExtracted("store");

  const [query, setQuery] = useQueryStates(parsers, {
    shallow: false,
    clearOnDefault: true,
  });

  const sorts = [
    { value: "newest", label: t("Newest") },
    { value: "price_asc", label: t("Price, low to high") },
    { value: "price_desc", label: t("Price, high to low") },
    { value: "title", label: t("Name") },
  ] as const;

  return (
    <div className="flex flex-wrap items-end gap-4">
      <InputGroup className="w-full max-w-sm">
        <InputGroupAddon>
          <SearchIcon />
        </InputGroupAddon>
        <InputGroupInput
          type="search"
          value={query.q}
          placeholder={t("Search the store")}
          aria-label={t("Search the store")}
          onChange={(event) => {
            void setQuery(
              { q: event.target.value },
              { limitUrlUpdates: debounce(250) },
            );
          }}
        />
      </InputGroup>
      <Select
        value={query.sort}
        items={sorts}
        onValueChange={(value) => {
          const sort = STORE_SORTS.find((candidate) => candidate === value);

          if (sort !== undefined) {
            void setQuery({ sort });
          }
        }}
      >
        <SelectTrigger aria-label={t("Sort by")} className="w-48">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {sorts.map((sort) => (
            <SelectItem key={sort.value} value={sort.value}>
              {sort.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Field orientation="horizontal" className="w-fit">
        <Checkbox
          id="store-in-stock"
          checked={query.stock}
          onCheckedChange={(checked) => {
            void setQuery({ stock: checked });
          }}
        />
        <FieldLabel htmlFor="store-in-stock">{t("In stock only")}</FieldLabel>
      </Field>
    </div>
  );
}
