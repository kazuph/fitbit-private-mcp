# fitbit-private-mcp

Fitbitの健康データをCloudflare D1へ同期し、Cloudflare Accessで保護した日本語の健康アクションダッシュボードと、API keyで保護したMCP endpointを提供する個人用Cloudflare Workerです。

構成とbuild gateは [mizchi/cloudflare-starterkit-mbt](https://github.com/mizchi/cloudflare-starterkit-mbt) を基準にしています。MoonBitでアプリケーションロジックを実装し、TypeScriptのWorker entrypointをWranglerがbundleします。

## 必要なツール

- Node.js 24以降
- pnpm 10.33.0
- MoonBit CLI
- Cloudflare Wrangler

## セットアップ

```sh
pnpm install
moon update
cp .env.example .env
```

ローカルWorker用のsecretは `.dev.vars` に設定します。`.env` と `.dev.vars` はgit管理外です。

ローカルD1を初期化して起動します。

```sh
pnpm run db:migrate
pnpm run dev
```

アプリは `http://localhost:18787` で起動します。

## 検証

```sh
pnpm run lint:secretlint
pnpm run build
pnpm run check
pnpm test
```

`pnpm run build` はMoonBitのrelease buildだけで終了せず、Wranglerのdeploy dry-runで実際のWorker bundleを生成し、bundle size、制御文字、MCP cron route、scheduled handlerを検査します。

## Cloudflare

`wrangler.jsonc` のD1 bindingは `DB`、static assetsは `static/`、cronは6時間ごとの同期と22:00 UTCの毎朝の健康アクション通知です。ダッシュボードはCloudflare Accessで保護し、MCP endpointはAPI keyで保護します。secret値は設定ファイルへ書かず、`wrangler secret put` で登録します。

```sh
pnpm exec wrangler secret put FITBIT_CLIENT_ID
pnpm exec wrangler secret put FITBIT_CLIENT_SECRET
pnpm exec wrangler secret put FITBIT_REDIRECT_URI
pnpm exec wrangler secret put MCP_API_KEY
pnpm exec wrangler secret put SLACK_BOT_TOKEN
```

deploy前には必ずbuild gateを通します。

```sh
pnpm run deploy
```
