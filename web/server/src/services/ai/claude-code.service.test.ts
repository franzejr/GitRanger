import { describe, it, expect, vi, beforeEach } from 'vitest';

const { mockExecFile } = vi.hoisted(() => {
  const mockExecFile = vi.fn();
  return { mockExecFile };
});

vi.mock('child_process', () => ({
  execFile: mockExecFile,
}));

vi.mock('util', () => ({
  promisify: () => mockExecFile,
}));

import { ClaudeCodeService } from './claude-code.service.js';

describe('ClaudeCodeService', () => {
  let service: ClaudeCodeService;

  beforeEach(() => {
    service = new ClaudeCodeService();
    vi.clearAllMocks();
  });

  describe('isAvailable', () => {
    it('returns true when claude CLI is found', async () => {
      mockExecFile.mockResolvedValueOnce({ stdout: '/usr/local/bin/claude\n' });
      expect(await service.isAvailable()).toBe(true);
    });

    it('returns false when claude CLI is not found', async () => {
      mockExecFile.mockRejectedValueOnce(new Error('not found'));
      expect(await service.isAvailable()).toBe(false);
    });
  });

  describe('summarize', () => {
    const mockSummary = {
      one_liner: 'Fix null pointer crash',
      explanation: 'Added guard clause.',
      impact: 'patch',
      categories: ['bugfix'],
      related_files: ['src/auth.ts'],
      risk_notes: null,
    };

    const envelope = {
      type: 'result',
      subtype: 'success',
      is_error: false,
      result: JSON.stringify(mockSummary),
      cost_usd: 0.003,
    };

    it('calls claude CLI and parses envelope response', async () => {
      mockExecFile.mockResolvedValueOnce({ stdout: JSON.stringify(envelope) });

      const result = await service.summarize('fix: crash', 'diff content');

      expect(result.one_liner).toBe('Fix null pointer crash');
      expect(result.related_files).toEqual(['src/auth.ts']);

      const [binary, args] = mockExecFile.mock.calls[0];
      expect(binary).toBe('claude');
      expect(args).toContain('-p');
      expect(args).toContain('--output-format');
      expect(args).toContain('json');
    });

    it('sets cwd in execFile options when repoPath is provided', async () => {
      mockExecFile.mockResolvedValueOnce({ stdout: JSON.stringify(envelope) });

      await service.summarize('fix: crash', 'diff', '/path/to/repo');

      const options = mockExecFile.mock.calls[0][2];
      expect(options.cwd).toBe('/path/to/repo');
    });

    it('throws when Claude Code returns an error', async () => {
      const errorEnvelope = {
        type: 'result',
        subtype: 'error',
        is_error: true,
        result: 'Authentication required',
      };
      mockExecFile.mockResolvedValueOnce({
        stdout: JSON.stringify(errorEnvelope),
      });

      await expect(service.summarize('msg', 'diff')).rejects.toThrow(
        'Claude Code error: Authentication required'
      );
    });
  });
});
