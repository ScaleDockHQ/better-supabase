"use client";

import type { ReactNode } from "react";

import { FilterXIcon } from "lucide-react";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import {
  ALL,
  filterRecipes,
  isFiltering,
  NO_FILTER,
  type RecipeFilter,
  type RecipeKind,
  recipeKinds,
  type RecipeSummary,
} from "@/lib/recipe-filter";
import { type RecipePlatform, recipePlatforms } from "@/lib/recipe-platform";

import { RecipeTile } from "./recipe-tile";

const PLATFORM_LABEL = {
  web: "Web",
  native: "Native",
} as const satisfies Record<RecipePlatform, string>;

const KIND_LABEL = {
  component: "Components",
  screen: "Screens",
} as const satisfies Record<RecipeKind, string>;

const isPlatform = (value: unknown): value is RecipePlatform =>
  recipePlatforms.some((platform) => platform === value);

const isKind = (value: unknown): value is RecipeKind =>
  recipeKinds.some((kind) => kind === value);

/**
 * Filters the available recipes by category, platform and kind. With no
 * filter it shows `children`, the category sections rendered on the server.
 */
export function RecipeFilters({
  recipes,
  categories,
  children,
}: {
  recipes: readonly RecipeSummary[];
  categories: readonly string[];
  children: ReactNode;
}) {
  const [filter, setFilter] = useState<RecipeFilter>(NO_FILTER);
  const categoryId = useId();
  const filtering = isFiltering(filter);
  const matches = filtering ? filterRecipes(recipes, filter) : [];

  const categoryItems = [
    { value: ALL, label: "All categories" },
    ...categories.map((category) => ({ value: category, label: category })),
  ];

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <label htmlFor={categoryId} className="sr-only">
            Category
          </label>
          <Select
            value={filter.category}
            items={categoryItems}
            onValueChange={(value) => {
              const item = categoryItems.find((each) => each.value === value);

              setFilter((current) => ({
                ...current,
                category: item?.value ?? ALL,
              }));
            }}
          >
            <SelectTrigger id={categoryId} size="sm" className="w-52">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {categoryItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <ToggleGroup
            aria-label="Platform"
            variant="outline"
            size="sm"
            spacing={0}
            value={[filter.platform]}
            onValueChange={(value) => {
              const next = value[0];

              setFilter((current) => ({
                ...current,
                platform: isPlatform(next) ? next : ALL,
              }));
            }}
          >
            <ToggleGroupItem value={ALL}>All platforms</ToggleGroupItem>
            {recipePlatforms.map((platform) => (
              <ToggleGroupItem key={platform} value={platform}>
                {PLATFORM_LABEL[platform]}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
          <ToggleGroup
            aria-label="Kind"
            variant="outline"
            size="sm"
            spacing={0}
            value={[filter.kind]}
            onValueChange={(value) => {
              const next = value[0];

              setFilter((current) => ({
                ...current,
                kind: isKind(next) ? next : ALL,
              }));
            }}
          >
            <ToggleGroupItem value={ALL}>All kinds</ToggleGroupItem>
            {recipeKinds.map((kind) => (
              <ToggleGroupItem key={kind} value={kind}>
                {KIND_LABEL[kind]}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>
        <p className="text-xs text-muted-foreground" aria-live="polite">
          {filtering
            ? `${String(matches.length)} of ${String(recipes.length)} recipes match`
            : null}
        </p>
      </div>
      {filtering ? (
        matches.length === 0 ? (
          <Empty className="border border-dashed border-border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FilterXIcon aria-hidden="true" />
              </EmptyMedia>
              <EmptyTitle>No recipe matches</EmptyTitle>
              <EmptyDescription>
                No available recipe has this category, platform and kind. The
                planned recipes are listed under their category.
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  setFilter(NO_FILTER);
                }}
              >
                Clear the filters
              </Button>
            </EmptyContent>
          </Empty>
        ) : (
          <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {matches.map((recipe) => (
              <li key={recipe.slug}>
                <RecipeTile recipe={recipe} />
              </li>
            ))}
          </ul>
        )
      ) : (
        children
      )}
    </div>
  );
}
