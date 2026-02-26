import { describe, it, expect, vi, beforeEach } from 'vitest';
import { OllamaService } from './ollama.service.js';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

describe('OllamaService', () => {
  let service: OllamaService;

  beforeEach(() => {
    service = new OllamaService();
    vi.clearAllMocks();
  });

  describe('isAvailable', () => {
    it('returns true when Ollama responds ok', async () => {
      mockFetch.mockResolvedValueOnce({ ok: true });
      expect(await service.isAvailable()).toBe(true);
      expect(mockFetch).toHaveBeenCalledWith('http://localhost:11434/api/tags');
    });

    it('returns false when fetch throws', async () => {
      mockFetch.mockRejectedValueOnce(new Error('ECONNREFUSED'));
      expect(await service.isAvailable()).toBe(false);
    });

    it('returns false when response is not ok', async () => {
      mockFetch.mockResolvedValueOnce({ ok: false });
      expect(await service.isAvailable()).toBe(false);
    });
  });

  describe('summarize', () => {
    const mockSummary = {
      one_liner: 'Fix null crash',
      explanation: 'Added guard clause.',
      impact: 'patch',
      categories: ['bugfix'],
    };

    it('posts to Ollama and parses response', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ response: JSON.stringify(mockSummary) }),
      });

      const result = await service.summarize('fix: crash', 'diff content');

      expect(result.one_liner).toBe('Fix null crash');
      expect(result.impact).toBe('patch');
      expect(mockFetch).toHaveBeenCalledWith(
        'http://localhost:11434/api/generate',
        expect.objectContaining({ method: 'POST' })
      );
    });

    it('throws on HTTP error', async () => {
      mockFetch.mockResolvedValueOnce({ ok: false, status: 500 });
      await expect(service.summarize('msg', 'diff')).rejects.toThrow('Ollama: HTTP 500');
    });

    it('uses custom model and base URL', async () => {
      const custom = new OllamaService('codellama', 'http://gpu-server:11434');
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ response: JSON.stringify(mockSummary) }),
      });

      await custom.summarize('msg', 'diff');

      const [url, options] = mockFetch.mock.calls[0];
      expect(url).toBe('http://gpu-server:11434/api/generate');
      const body = JSON.parse(options.body);
      expect(body.model).toBe('codellama');
    });
  });
});
