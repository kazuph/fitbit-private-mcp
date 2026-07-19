// MoonBit CPS-to-Promise wrapper
import {
  post_error_to_slack,
} from '../../_build/js/release/build/server/server.js';

type Cont<T> = (result: T) => undefined;
type ErrCont = (error: unknown) => undefined;
const cps = <T>(fn: (cont: Cont<T>, errorCont: ErrCont) => unknown): Promise<T> =>
  new Promise((resolve, reject) => fn(
    (result) => { resolve(result); return undefined; },
    (error) => { reject(error); return undefined; },
  ));

export const postErrorToSlack = (error: Error, context?: string) =>
  cps<boolean>((c, e) => post_error_to_slack(error.message || String(error), context, c, e));
