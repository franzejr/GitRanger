import { describe, it, expect, vi, beforeEach } from 'vitest';
import { AnthropicAPIService } from './anthropic.service.js';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

describe('AnthropicAPIService', () => {
  let service: AnthropicAPIService;

  beforeEach(() => {
    service = new AnthropicAPIService('sk-test-key');
    vi.clearAllMocks();
  });

  describe('isAvailable', () => {
    it('returns true when API key is present', async () => {
      expect(await service.isAvailable()).toBe(true);
    });

    it('returns false when API key is empty', async () => {
      const empty = new AnthropicAPIService('');
      expect(await empty.isAvailable()).toBe(false);
    });
  });

  describe('summarize', () => {
    const mockSummary = {
      one_liner: 'Add user validation',
      explanation: 'Validates email format before saving.',
      impact: 'minor',
      categories: ['feature'],
    };

    it('calls Anthropic API and parses response', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          content: [{ type: 'text', text: JSON.stringify(mockSummary) }],
        }),
      });

      const result = await service.summarize('feat: validation', 'diff');

      expect(result.one_liner).toBe('Add user validation');
      expect(mockFetch).toHaveBeenCalledWith(
        'https://api.anthropic.com/v1/messages',
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            'x-api-key': 'sk-test-key',
            'anthropic-version': '2023-06-01',
          }),
        })
      );
    });

    it('throws on HTTP error', async () => {
      mockFetch.mockResolvedValueOnce({ ok: false, status: 401 });
      await expect(service.summarize('msg', 'diff')).rejects.toThrow('Anthropic API: HTTP 401');
    });
  });
});
