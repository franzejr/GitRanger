import express from 'express';
import cors from 'cors';
import { runMigrations } from './db/migrate.js';
import { healthRouter } from './routes/health.js';
import { reposRouter } from './routes/repos.js';
import { commitsRouter } from './routes/commits.js';

// Run database migrations
runMigrations();

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

// Routes
app.use('/api/health', healthRouter);
app.use('/api/repos', reposRouter);
app.use('/api/commits', commitsRouter);

// Error handling middleware
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`GitNarrate server running on http://localhost:${PORT}`);
});
