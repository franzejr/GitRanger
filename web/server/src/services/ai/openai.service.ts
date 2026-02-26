import type { AIService, CommitSummary } from '../../types/index.js';
import { buildPrompt, parseCommitSummary } from './prompt.js';

interface OpenAIResponse {
  choices: Array<{
    message: { content: string };
  }>;
}

export class OpenAIService implements AIService {
  readonly name = 'OpenAI API';
  readonly requiresAPIKey = true;

  constructor(
    private readonly apiKey: string,
    private readonly model: string = 'gpt-4o'
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

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: 'You analyze git commit diffs and return structured JSON summaries.',
          },
          {
            role: 'user',
            content: buildPrompt(commitMessage, truncatedDiff),
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI API: HTTP ${response.status}`);
    }

    const data = (await response.json()) as OpenAIResponse;
    const text = data.choices[0]?.message?.content ?? '';
    return parseCommitSummary(text);
  }

  async generate(prompt: string, _repoPath?: string): Promise<string> {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: this.model,
        messages: [
          { role: 'user', content: prompt },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI API: HTTP ${response.status}`);
    }

    const data = (await response.json()) as OpenAIResponse;
    return data.choices[0]?.message?.content ?? '';
  }
}
