# MoonBit + Cloudflare Workers 構成移行レビュー

## 元の依頼

> mizchiさんのgithubにmoonbit + cloudflareのベスプラリポジトリがあるので、まずそれを見つけて。見つけたらそれに合わせてこのアプリケーションを改変します。

## 未達・未確認

- Cloudflare本番へのデプロイは依頼範囲外のため実施していません。ローカルのWrangler dry-run bundleまで検証済みです。
- Fitbit実アカウントを必要とするOAuth完走・トークン保存・更新など6件はE2Eでskipされています。認可URL、callback失敗処理、D1を使わない境界テストは通っています。
- Solが自動生成する `app/__gen__/server/main.mbt` に `unused_async` 警告が1件あります。生成コード以外のMoonBitソースはformat/checkを通過しています。
- 既存UIの補助診断では、active navのコントラストとモバイル時の高さ38pxが指摘されています。今回のMoonBit/Cloudflare構成移行ではUIを変更していません。

## WHY — 移行前の問題

移行前は古いLuna/Sol API、npmとpnpmの二重lockfile、MoonBitの旧package manifest、release指定のないbuild、bundle検査のないdeploy構成が混在し、現行MoonBitコンパイラではbaseline buildが失敗していました。

また、TypeScriptからMoonBitのasync exportを直接呼ぶ経路は、Cloudflareのcron処理でMoonBit coroutine外からD1のPromiseを待機してpanicしました。MCPのレスポンスも既存E2Eが要求する `{ success, data: { <resource>, period } }` と一致していませんでした。

参照実装として見つけたのは [mizchi/cloudflare-starterkit-mbt](https://github.com/mizchi/cloudflare-starterkit-mbt) です。MoonBit、Cloudflare Workers、D1、Sol、pnpm、Wrangler、CI/CDを組み合わせたopinionated starterとして、そのうち現アプリに必要な構成だけを採用しました。

## HOW — 採用した方針

- pnpmを唯一のpackage managerにし、Node/pnpm/Wrangler/Sol/secretlintの実行条件を固定しました。7日以内に公開されたnpm packageを避ける設定もworkspaceに追加しています。
- MoonBitは現在のsplit package構成へ移行し、package manifestを `moon.pkg` に更新しました。Sol 0.22.1がmodule manifestとして `moon.mod.json` のみを読むため、module manifestだけはJSON形式を維持しています。
- Workers入口はHonoでBasic AuthとMCP API keyを検証し、Sol/MoonBit処理は同じ `ExecutionContext` とrequest-localなenv/D1を渡して実行します。
- D1を使う同期、OAuth、Slack、report、cronはSolの内部POST routeに集約し、MoonBit coroutine内で実行するようにしました。
- release build後にWrangler dry-run bundleを生成し、成果物のサイズ、制御文字、manual cron route、scheduled handlerを機械検査します。
- 参照repoのPulumi、R2、OTLP、sqlc、staging自動デプロイは、現アプリに対応リソースや要件がないため追加していません。

## WHAT — 現在の状態

- `pnpm run build`: 成功。Sol生成、MoonBit release build、Cloudflare dry-run、bundle検査まで完走。
- 最終Worker bundle: `dist/worker.js`、2,311,464 bytes、gzip upload 248.31 KiB。
- `pnpm run check`: 0 errors。生成コード由来の警告1件のみ。
- MoonBit source format check: 成功。
- tracked/untracked対象のsecretlint: 成功。
- `pnpm test`: 45件中39 passed、6 skipped、0 failed、31.3秒。
- axe-core: violations 0、passes 15。
- `git diff --check`: 成功。

主な変更箇所は `package.json` / `pnpm-workspace.yaml`、`moon.mod.json` / `app/*/moon.pkg`、`src/worker.ts`、`app/server/api.mbt`、`wrangler.jsonc`、`.github/workflows/ci.yml`、`scripts/check-worker-bundle.ts`、`worker-configuration.d.ts` です。

## 実ブラウザ証跡

Playwrightが起動したローカルWrangler WorkerをChromiumで操作し、Basic Auth、dashboard、MCP、OAuth境界、cron、accessibilityを検証しました。

![最終SSRダッシュボード](/tmp/dashboard-full.png)

## 承認してほしい内容

本番デプロイを行わず、mizchiのstarterから現アプリに必要な依存管理、release bundle、Workers設定、request-local context、CI、secret scanだけを取り込んだ今回の移行を承認してください。
