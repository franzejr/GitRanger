import { describe, it, expect } from 'vitest';
import { buildPrompt, parseCommitSummary } from './prompt.js';

describe('buildPrompt', () => {
  it('includes commit message and diff in the prompt', () => {
    const result = buildPrompt('fix: null crash', '--- a/file.ts\n+++ b/file.ts');

    expect(result).toContain('fix: null crash');
    expect(result).toContain('--- a/file.ts');
    expect(result).toContain('one_liner');
    expect(result).toContain('impact');
  });
});

describe('parseCommitSummary', () => {
  const validSummary = {
    one_liner: 'Fix null pointer crash',
    explanation: 'Added guard clause for null sessions.',
    impact: 'patch',
    categories: ['bugfix'],
  };

  it('parses valid JSON string', () => {
    const result = parseCommitSummary(JSON.stringify(validSummary));

    expect(result.one_liner).toBe('Fix null pointer crash');
    expect(result.impact).toBe('patch');
    expect(result.categories).toEqual(['bugfix']);
  });

  it('strips markdown code fences', () => {
    const wrapped = '```json\n' + JSON.stringify(validSummary) + '\n```';
    const result = parseCommitSummary(wrapped);

    expect(result.one_liner).toBe('Fix null pointer crash');
  });

  it('preserves optional fields', () => {
    const withOptional = {
      ...validSummary,
      related_files: ['src/auth.ts'],
      risk_notes: 'May affect session handling',
    };
    const result = parseCommitSummary(JSON.stringify(withOptional));

    expect(result.related_files).toEqual(['src/auth.ts']);
    expect(result.risk_notes).toBe('May affect session handling');
  });

  it('throws on invalid JSON', () => {
    expect(() => parseCommitSummary('not json')).toThrow();
  });

  it('throws when required fields are missing', () => {
    const incomplete = { one_liner: 'test' };
    expect(() => parseCommitSummary(JSON.stringify(incomplete))).toThrow(
      'AI response missing required fields'
    );
  });
});
