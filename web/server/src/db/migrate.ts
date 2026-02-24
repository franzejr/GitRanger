import db from './index.js';
import { up as migration001 } from './migrations/001_initial_schema.js';

interface Migration {
  name: string;
  up: (db: typeof import('better-sqlite3').prototype) => void;
}

const migrations: Migration[] = [
  { name: '001_initial_schema', up: migration001 },
];

export function runMigrations(): void {
  console.log('Running database migrations...');

  // Ensure migrations table exists (bootstrap)
  db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  const appliedMigrations = db
    .prepare('SELECT name FROM migrations')
    .all() as { name: string }[];

  const appliedSet = new Set(appliedMigrations.map((m) => m.name));

  for (const migration of migrations) {
    if (appliedSet.has(migration.name)) {
      console.log(`  ✓ ${migration.name} (already applied)`);
      continue;
    }

    console.log(`  → Applying ${migration.name}...`);

    db.transaction(() => {
      migration.up(db);
      db.prepare('INSERT INTO migrations (name) VALUES (?)').run(migration.name);
    })();

    console.log(`  ✓ ${migration.name} applied`);
  }

  console.log('Migrations complete.');
}

// Run migrations if this file is executed directly
if (process.argv[1]?.endsWith('migrate.ts') || process.argv[1]?.endsWith('migrate.js')) {
  runMigrations();
}
