import { spawn } from 'child_process';
import { execFile } from 'child_process';
import { promisify } from 'util';
import type { AIService, CommitSummary } from '../../types/index.js';
import { buildPrompt, parseCommitSummary } from './prompt.js';

const execFileAsync = promisify(execFile);

interface ClaudeCodeEnvelope {
  type: string;
  subtype: string;
  is_error: boolean;
  result: string;
  cost_usd?: number;
}

export class ClaudeCodeService implements AIService {
  readonly name = 'Claude Code (Local)';
  readonly requiresAPIKey = false;

  async isAvailable(): Promise<boolean> {
    try {
      await execFileAsync('which', ['claude']);
      return true;
    } catch {
      return false;
    }
  }

  async summarize(
    commitMessage: string,
    diff: string,
    repoPath?: string
  ): Promise<CommitSummary> {
    const truncatedDiff = diff.slice(0, 12000);
    const prompt = buildPrompt(commitMessage, truncatedDiff);

    console.log(`[claude-code] cwd: ${repoPath ?? '(none)'}`);
    console.log(`[claude-code] prompt length: ${prompt.length} chars`);
    console.log(`[claude-code] spawning: claude -p --output-format json --model haiku (stdin piped)`);

    // Strip CLAUDECODE env var so we can spawn claude from within a claude session
    const env = { ...process.env };
    delete env.CLAUDECODE;

    const stdout = await new Promise<string>((resolve, reject) => {
      const child = spawn('claude', [
        '-p',
        '--output-format', 'json',
        '--model', 'haiku',
        '--no-session-persistence',
      ], {
        cwd: repoPath,
        env,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      let out = '';
      let err = '';

      child.stdout.on('data', (data: Buffer) => {
        out += data.toString();
      });

      child.stderr.on('data', (data: Buffer) => {
        const msg = data.toString();
        err += msg;
        console.log(`[claude-code] stderr: ${msg.trim()}`);
      });

      child.on('error', (e) => reject(e));

      child.on('close', (code) => {
        if (code !== 0) {
          reject(new Error(`claude exited with code ${code}: ${err}`));
        } else {
          resolve(out);
        }
      });

      // Send prompt via stdin and close it
      child.stdin.write(prompt);
      child.stdin.end();

      // Timeout after 60s
      setTimeout(() => {
        child.kill();
        reject(new Error('Claude Code timed out after 60s'));
      }, 60000);
    });

    console.log(`[claude-code] raw stdout (first 500 chars): ${stdout.slice(0, 500)}`);

    const envelope = JSON.parse(stdout) as ClaudeCodeEnvelope;

    if (envelope.is_error) {
      throw new Error(`Claude Code error: ${envelope.result}`);
    }

    const summary = parseCommitSummary(envelope.result);
    console.log(`[claude-code] parsed summary:`, JSON.stringify(summary));
    return summary;
  }

  async generate(prompt: string, repoPath?: string): Promise<string> {
    console.log(`[claude-code] generate cwd: ${repoPath ?? '(none)'}`);
    console.log(`[claude-code] generate prompt length: ${prompt.length} chars`);

    const env = { ...process.env };
    delete env.CLAUDECODE;

    const stdout = await new Promise<string>((resolve, reject) => {
      const child = spawn('claude', [
        '-p',
        '--output-format', 'json',
        '--model', 'haiku',
        '--no-session-persistence',
      ], {
        cwd: repoPath,
        env,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      let out = '';
      let err = '';

      child.stdout.on('data', (data: Buffer) => {
        out += data.toString();
      });

      child.stderr.on('data', (data: Buffer) => {
        const msg = data.toString();
        err += msg;
        console.log(`[claude-code] generate stderr: ${msg.trim()}`);
      });

      child.on('error', (e) => reject(e));

      child.on('close', (code) => {
        if (code !== 0) {
          reject(new Error(`claude exited with code ${code}: ${err}`));
        } else {
          resolve(out);
        }
      });

      child.stdin.write(prompt);
      child.stdin.end();

      setTimeout(() => {
        child.kill();
        reject(new Error('Claude Code timed out after 120s'));
      }, 120000);
    });

    const envelope = JSON.parse(stdout) as ClaudeCodeEnvelope;

    if (envelope.is_error) {
      throw new Error(`Claude Code error: ${envelope.result}`);
    }

    return envelope.result;
  }
}
