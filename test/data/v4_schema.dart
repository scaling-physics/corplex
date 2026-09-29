/// The schema as shipped at v4 (dumped from the last pre-sync commit), so
/// the v4 -> v5 migration is tested against the real thing.
const v4SchemaStatements = [
  r'''CREATE TABLE "folders" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))''',
  r'''CREATE TABLE "notes" ("id" TEXT NOT NULL, "title" TEXT NOT NULL DEFAULT '', "content" TEXT NOT NULL DEFAULT '', "folder_id" TEXT NULL REFERENCES folders (id) ON DELETE SET NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))''',
  r'''CREATE TABLE "papers" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, "authors" TEXT NOT NULL DEFAULT '', "year" INTEGER NULL, "venue" TEXT NULL, "doi" TEXT NULL, "pdf_path" TEXT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))''',
  r'''CREATE TABLE "attachments" ("id" TEXT NOT NULL, "note_id" TEXT NULL REFERENCES notes (id) ON DELETE CASCADE, "paper_id" TEXT NULL REFERENCES papers (id) ON DELETE CASCADE, "type" TEXT NOT NULL, "title" TEXT NULL, "path" TEXT NULL, "url" TEXT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))''',
  r'''CREATE TABLE "note_paper_refs" ("note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "paper_id" TEXT NOT NULL REFERENCES papers (id) ON DELETE CASCADE, PRIMARY KEY ("note_id", "paper_id"))''',
  r'''CREATE TABLE "annotations" ("id" TEXT NOT NULL, "paper_id" TEXT NOT NULL REFERENCES papers (id) ON DELETE CASCADE, "page_number" INTEGER NOT NULL, "color_hex" TEXT NOT NULL DEFAULT '#FFEB3B', "points_json" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))''',
  r'''CREATE TABLE "tags" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))''',
  r'''CREATE TABLE "note_tags" ("note_id" TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE, "tag_id" TEXT NOT NULL REFERENCES tags (id) ON DELETE CASCADE, PRIMARY KEY ("note_id", "tag_id"))''',
];
