import axios from 'axios';
import { axiosWithRetry } from './retry';

jest.mock('axios');

const mockedAxios = axios as jest.Mocked<typeof axios>;

describe('axiosWithRetry', () => {
  beforeEach(() => {
    mockedAxios.request.mockReset();
  });

  test('retries until success within maxAttempts', async () => {
    const error = new Error('network');
    mockedAxios.request
      .mockRejectedValueOnce(error)
      .mockRejectedValueOnce(error)
      .mockResolvedValue({ data: { ok: true } } as any);

    const result = await axiosWithRetry<{ ok: boolean }>({ url: 'https://example.com', method: 'get' }, 3, 0);

    expect(result).toEqual({ ok: true });
    expect(mockedAxios.request).toHaveBeenCalledTimes(3);
  });

  test('stops after reaching the maximum attempts', async () => {
    const error = new Error('timeout');
    mockedAxios.request.mockRejectedValue(error);

    await expect(axiosWithRetry({ url: 'https://fail.example', method: 'get' }, 2, 0)).rejects.toThrow('timeout');
    expect(mockedAxios.request).toHaveBeenCalledTimes(2);
  });
});
