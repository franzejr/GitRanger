import { describe, it, expect, vi, beforeEach } from 'vitest';
import { OpenAIService } from './openai.service.js';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

describe('OpenAIService', () => {
  let service: OpenAIService;

  beforeEach(() => {
    service = new OpenAIService('sk-test-key');
    vi.clearAllMocks();
  });

  describe('isAvailable', () => {
    it('returns true when API key is present', async () => {
      expect(await service.isAvailable()).toBe(true);
    });

    it('returns false when API key is empty', async () => {
      const empty = new OpenAIService('');
      expect(await empty.isAvailable()).toBe(false);
    });
  });

  describe('summarize', () => {
    const mockSummary = {
      one_liner: 'Refactor auth module',
      explanation: 'Extracted validation into separate service.',
      impact: 'patch',
      categories: ['refactor'],
    };

    it('calls OpenAI API and parses response', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          choices: [{ message: { content: JSON.stringify(mockSummary) } }],
        }),
      });

      const result = await service.summarize('refactor: auth', 'diff');

      expect(result.one_liner).toBe('Refactor auth module');
      expect(mockFetch).toHaveBeenCalledWith(
        'https://api.openai.com/v1/chat/completions',
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            Authorization: 'Bearer sk-test-key',
          }),
        })
      );

      const body = JSON.parse(mockFetch.mock.calls[0][1].body);
      expect(body.response_format).toEqual({ type: 'json_object' });
    });

    it('throws on HTTP error', async () => {
      mockFetch.mockResolvedValueOnce({ ok: false, status: 429 });
      await expect(service.summarize('msg', 'diff')).rejects.toThrow('OpenAI API: HTTP 429');
    });
  });
});
