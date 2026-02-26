import db from '../../db/index.js';
import type { SettingRow } from '../../db/index.js';
import type { AIService, AIProvider } from '../../types/index.js';
import { ClaudeCodeService } from './claude-code.service.js';
import { AnthropicAPIService } from './anthropic.service.js';
import { OpenAIService } from './openai.service.js';
import { OllamaService } from './ollama.service.js';

class AIServiceFactory {
  private getSetting(key: string): string {
    const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key) as
      | SettingRow
      | undefined;
    return row?.value ?? '';
  }

  private setSetting(key: string, value: string): void {
    const now = new Date().toISOString();
    db.prepare(
      `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
    ).run(key, value, now);
  }

  getActiveProvider(): AIService {
    const provider = (this.getSetting('ai_provider') || 'claude_code') as AIProvider;
    return this.createProvider(provider);
  }

  getActiveProviderName(): AIProvider {
    return (this.getSetting('ai_provider') || 'claude_code') as AIProvider;
  }

  createProvider(provider: AIProvider): AIService {
    switch (provider) {
      case 'claude_code':
        return new ClaudeCodeService();
      case 'anthropic_api':
        return new AnthropicAPIService(
          this.getSetting('anthropic_api_key'),
          this.getSetting('anthropic_model') || undefined
        );
      case 'openai':
        return new OpenAIService(
          this.getSetting('openai_api_key'),
          this.getSetting('openai_model') || undefined
        );
      case 'ollama':
        return new OllamaService(
          this.getSetting('ollama_model') || undefined,
          this.getSetting('ollama_url') || undefined
        );
    }
  }

  async autoDetect(): Promise<AIProvider> {
    const claudeCode = new ClaudeCodeService();
    if (await claudeCode.isAvailable()) return 'claude_code';
    if (this.getSetting('anthropic_api_key')) return 'anthropic_api';
    if (this.getSetting('openai_api_key')) return 'openai';
    const ollama = new OllamaService();
    if (await ollama.isAvailable()) return 'ollama';
    return 'claude_code';
  }

  setProviderConfig(provider: AIProvider, config: Record<string, string>): void {
    this.setSetting('ai_provider', provider);
    for (const [key, value] of Object.entries(config)) {
      this.setSetting(key, value);
    }
  }

  async getStatus(): Promise<
    Array<{
      provider: AIProvider;
      name: string;
      available: boolean;
      requiresAPIKey: boolean;
    }>
  > {
    const providers: AIProvider[] = ['claude_code', 'anthropic_api', 'openai', 'ollama'];
    return Promise.all(
      providers.map(async (p) => {
        const service = this.createProvider(p);
        return {
          provider: p,
          name: service.name,
          available: await service.isAvailable(),
          requiresAPIKey: service.requiresAPIKey,
        };
      })
    );
  }
}

export const aiServiceFactory = new AIServiceFactory();
