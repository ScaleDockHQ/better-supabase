-- Foreign keys on the project page need a leading index.
create index if not exists "collection_star_folders_user_idx" on "better_supabase"."collection_star_folders" ("user_id");
create index if not exists "collection_favorites_folder_idx" on "better_supabase"."collection_favorites" ("folder_id") where "folder_id" is not null;
