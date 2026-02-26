import type { AIService, CommitSummary } from '../../types/index.js';
import { buildPrompt, parseCommitSummary } from './prompt.js';

interface OllamaGenerateResponse {
  response: string;
  done: boolean;
}

export class OllamaService implements AIService {
  readonly name = 'Ollama (Local)';
  readonly requiresAPIKey = false;

  constructor(
    private readonly model: string = 'llama3.2',
    private readonly baseUrl: string = 'http://localhost:11434'
  ) {}

  async isAvailable(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/api/tags`);
      return response.ok;
    } catch {
      return false;
    }
  }

  async summarize(
    commitMessage: string,
    diff: string,
    _repoPath?: string
  ): Promise<CommitSummary> {
    const truncatedDiff = diff.slice(0, 4000);
    const prompt = buildPrompt(commitMessage, truncatedDiff);

    const response = await fetch(`${this.baseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        prompt,
        stream: false,
        format: 'json',
      }),
    });

    if (!response.ok) {
      throw new Error(`Ollama: HTTP ${response.status}`);
    }

    const data = (await response.json()) as OllamaGenerateResponse;
    return parseCommitSummary(data.response);
  }

  async generate(prompt: string, _repoPath?: string): Promise<string> {
    const response = await fetch(`${this.baseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        prompt,
        stream: false,
      }),
    });

    if (!response.ok) {
      throw new Error(`Ollama: HTTP ${response.status}`);
    }

    const data = (await response.json()) as OllamaGenerateResponse;
    return data.response;
  }
}
