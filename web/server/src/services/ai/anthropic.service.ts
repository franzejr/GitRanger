import type { AIService, CommitSummary } from '../../types/index.js';
import { buildPrompt, parseCommitSummary } from './prompt.js';

interface AnthropicResponse {
  content: Array<{ type: string; text: string }>;
}

export class AnthropicAPIService implements AIService {
  readonly name = 'Anthropic API';
  readonly requiresAPIKey = true;

  constructor(
    private readonly apiKey: string,
    private readonly model: string = 'claude-sonnet-4-5-20250514'
  ) {}

  async isAvailable(): Promise<boolean> {
    return this.apiKey.length > 0;
  }

  async summarize(
    commitMessage: string,
    diff: string,
    _repoPath?: string
  ): Promise<CommitSummary> {
    const truncatedDiff = diff.slice(0, 8000);
    const content = buildPrompt(commitMessage, truncatedDiff);

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': this.apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: 600,
        messages: [{ role: 'user', content }],
      }),
    });

    if (!response.ok) {
      throw new Error(`Anthropic API: HTTP ${response.status}`);
    }

    const data = (await response.json()) as AnthropicResponse;
    const text = data.content[0]?.text ?? '';
    return parseCommitSummary(text);
  }

  async generate(prompt: string, _repoPath?: string): Promise<string> {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': this.apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: 2000,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    if (!response.ok) {
      throw new Error(`Anthropic API: HTTP ${response.status}`);
    }

    const data = (await response.json()) as AnthropicResponse;
    return data.content[0]?.text ?? '';
  }
}
