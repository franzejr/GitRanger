import { Router, Request, Response } from 'express';
import { aiServiceFactory } from '../services/ai/ai-factory.service.js';
import type { AIProvider } from '../types/index.js';

export const aiRouter = Router();

const VALID_PROVIDERS: AIProvider[] = ['claude_code', 'anthropic_api', 'openai', 'ollama'];

// GET /api/ai/status - Check which providers are available
aiRouter.get('/status', async (_req: Request, res: Response) => {
  try {
    const providers = await aiServiceFactory.getStatus();
    const activeProvider = aiServiceFactory.getActiveProviderName();

    res.json({ providers, activeProvider });
  } catch (error) {
    console.error('Error getting AI status:', error);
    res.status(500).json({ error: 'Failed to get AI status' });
  }
});

// PUT /api/ai/provider - Set active AI provider and config
aiRouter.put('/provider', async (req: Request, res: Response) => {
  const { provider, config = {} } = req.body as {
    provider: AIProvider;
    config?: Record<string, string>;
  };

  if (!provider || !VALID_PROVIDERS.includes(provider)) {
    res.status(400).json({
      error: `Invalid provider. Must be one of: ${VALID_PROVIDERS.join(', ')}`,
    });
    return;
  }

  try {
    aiServiceFactory.setProviderConfig(provider, config);
    res.json({ success: true, provider });
  } catch (error) {
    console.error('Error setting AI provider:', error);
    res.status(500).json({ error: 'Failed to set AI provider' });
  }
});
