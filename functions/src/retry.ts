import axios, { AxiosRequestConfig } from 'axios';

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

export async function axiosWithRetry<T>(config: AxiosRequestConfig, maxAttempts = 3, baseDelayMs = 200) : Promise<T> {
  let attempt = 0;
  let lastErr: any = null;
  while (attempt < maxAttempts) {
    try {
      const resp = await axios.request<T>(config);
      return resp.data;
    } catch (err:any) {
      lastErr = err;
      attempt++;
      const delay = baseDelayMs * Math.pow(2, attempt - 1);
      // jitter
      const jitter = Math.floor(Math.random() * Math.min(100, delay));
      const wait = delay + jitter;
      console.warn(JSON.stringify({ msg: 'axios_retry', attempt, wait, err: err?.message ?? String(err) }));
      if (attempt >= maxAttempts) break;
      await sleep(wait);
    }
  }
  throw lastErr;
}
