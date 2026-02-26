import { describe, it, expect, beforeEach } from 'vitest';
import { runMigrations } from '../../db/migrate.js';
import db from '../../db/index.js';
import { aiServiceFactory } from './ai-factory.service.js';

describe('AIServiceFactory', () => {
  beforeEach(() => {
    runMigrations();
    db.prepare('DELETE FROM settings').run();
  });

  describe('getActiveProviderName', () => {
    it('defaults to claude_code when no setting exists', () => {
      expect(aiServiceFactory.getActiveProviderName()).toBe('claude_code');
    });

    it('returns the configured provider', () => {
      db.prepare('INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)').run(
        'ai_provider',
        'ollama',
        new Date().toISOString()
      );
      expect(aiServiceFactory.getActiveProviderName()).toBe('ollama');
    });
  });

  describe('createProvider', () => {
    it('creates ClaudeCodeService for claude_code', () => {
      const provider = aiServiceFactory.createProvider('claude_code');
      expect(provider.name).toBe('Claude Code (Local)');
      expect(provider.requiresAPIKey).toBe(false);
    });

    it('creates AnthropicAPIService for anthropic_api', () => {
      const provider = aiServiceFactory.createProvider('anthropic_api');
      expect(provider.name).toBe('Anthropic API');
      expect(provider.requiresAPIKey).toBe(true);
    });

    it('creates OpenAIService for openai', () => {
      const provider = aiServiceFactory.createProvider('openai');
      expect(provider.name).toBe('OpenAI API');
      expect(provider.requiresAPIKey).toBe(true);
    });

    it('creates OllamaService for ollama', () => {
      const provider = aiServiceFactory.createProvider('ollama');
      expect(provider.name).toBe('Ollama (Local)');
      expect(provider.requiresAPIKey).toBe(false);
    });
  });

  describe('setProviderConfig', () => {
    it('writes provider and config to settings table', () => {
      aiServiceFactory.setProviderConfig('anthropic_api', {
        anthropic_api_key: 'sk-test-123',
        anthropic_model: 'claude-opus-4-6',
      });

      const provider = db
        .prepare('SELECT value FROM settings WHERE key = ?')
        .get('ai_provider') as { value: string };
      const key = db
        .prepare('SELECT value FROM settings WHERE key = ?')
        .get('anthropic_api_key') as { value: string };

      expect(provider.value).toBe('anthropic_api');
      expect(key.value).toBe('sk-test-123');
    });

    it('overwrites existing settings', () => {
      aiServiceFactory.setProviderConfig('ollama', {});
      aiServiceFactory.setProviderConfig('openai', { openai_api_key: 'sk-new' });

      expect(aiServiceFactory.getActiveProviderName()).toBe('openai');
    });
  });

  describe('getStatus', () => {
    it('returns status for all 4 providers', async () => {
      const statuses = await aiServiceFactory.getStatus();

      expect(statuses).toHaveLength(4);
      expect(statuses.map((s) => s.provider)).toEqual([
        'claude_code',
        'anthropic_api',
        'openai',
        'ollama',
      ]);
      expect(statuses.every((s) => typeof s.available === 'boolean')).toBe(true);
    });
  });
});
