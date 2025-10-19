import axios from 'axios';
import { askGooseAgent } from './engage';

jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

describe('Goose agent client', () => {
  afterEach(() => {
    jest.resetAllMocks();
  });

  test('falls back to heuristic when no URL configured', async () => {
    delete process.env.GOOSE_AGENT_URL;
    const res = await askGooseAgent({ type: 'app_open', ctx: { stats: { dropsCount: 0 } } });
    expect(res.action).toBe('message');
  });

  test('uses external Goose agent when configured', async () => {
    process.env.GOOSE_AGENT_URL = 'https://example.com/agent';
    mockedAxios.post.mockResolvedValue({ data: { action: 'none', reason: 'ok' } });
    const res = await askGooseAgent({ type: 'anything', ctx: {} });
    expect(mockedAxios.post).toHaveBeenCalled();
    expect(res.reason).toBe('ok');
  });

  test('handles agent errors gracefully', async () => {
    process.env.GOOSE_AGENT_URL = 'https://example.com/agent';
    mockedAxios.post.mockRejectedValue(new Error('timeout'));
    const res = await askGooseAgent({ type: 'anything', ctx: {} });
    expect(res.action).toBeDefined();
  });
});
