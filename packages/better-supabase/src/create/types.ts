/** One rendered file: its path, the SQL module it belongs to and its contents. */
export interface PresetMigrationFile {
  readonly path: string;
  readonly module: string;
  readonly contents: string;
}
