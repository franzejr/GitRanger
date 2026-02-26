import express from 'express';
import cors from 'cors';
import { healthRouter } from './routes/health.js';
import { reposRouter } from './routes/repos.js';
import { commitsRouter } from './routes/commits.js';
import { aiRouter } from './routes/ai.js';

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json());

  // Routes
  app.use('/api/health', healthRouter);
  app.use('/api/repos', reposRouter);
  app.use('/api/commits', commitsRouter);
  app.use('/api/ai', aiRouter);

  // Error handling middleware
  app.use(
    (
      err: Error,
      _req: express.Request,
      res: express.Response,
      _next: express.NextFunction
    ) => {
      console.error('Unhandled error:', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  );

  return app;
}
