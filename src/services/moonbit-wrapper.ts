// MoonBit CPS-to-Promise wrapper
import {
  post_to_slack, post_error_to_slack, exchange_auth_code, save_oauth_token,
  get_valid_access_token, update_daily_summary, sync_health_data, post_daily_health_report,
} from '../../target/js/release/build/server/server.js';

type Cont<T> = (r: T) => void;
type ErrCont = (e: Error) => void;
const cps = <T>(fn: (c: Cont<T>, e: ErrCont) => void): Promise<T> =>
  new Promise((res, rej) => fn(res, rej));

export interface FitbitTokenResponse {
  access_token: string; refresh_token: string; expires_in: number;
  token_type: string; user_id: string; scope?: string;
}

export const postToSlack = (text: string) =>
  cps<boolean>((c, e) => post_to_slack(text, c, e));

export const postErrorToSlack = (error: Error, context?: string) =>
  cps<boolean>((c, e) => post_error_to_slack(error.message || String(error), context, c, e));

export async function exchangeAuthCode(code: string, uri: string): Promise<FitbitTokenResponse | null> {
  const r = await cps<any>((c, e) => exchange_auth_code(code, uri, c, e));
  return r ?? null;
}

export const saveOAuthToken = (uid: string, at: string, rt: string, exp: string, scope: string) =>
  cps<void>((c, e) => save_oauth_token(uid, at, rt, exp, scope, c, e));

export const getValidAccessToken = (uid: string) =>
  cps<[string | null, string | null]>((c, e) => get_valid_access_token(uid, c, e));

export const calculateExpiry = (sec: number): string => new Date(Date.now() + sec * 1000).toISOString();

export const updateDailySummary = (date: string, vo2max: string | null = null, spo2: number | null = null) =>
  cps<void>((c, e) => update_daily_summary(date, vo2max, spo2, c, e));

export const syncHealthData = (token: string, date: string) =>
  cps<[string | null, number | null]>((c, e) => sync_health_data(token, date, c, e));

export const postDailyHealthReport = () =>
  cps<void>((c, e) => post_daily_health_report(c, e));
