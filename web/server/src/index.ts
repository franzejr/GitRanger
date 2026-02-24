import { runMigrations } from './db/migrate.js';
import { createApp } from './app.js';

// Run database migrations
runMigrations();

const app = createApp();
const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`GitNarrate server running on http://localhost:${PORT}`);
});
