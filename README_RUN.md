Run / debug instructions (development)

1) Install dependencies (using Bundler):

```bash
gem install bundler
bundle install
```

2) Set Telegram token (example):

```bash
export TELEGRAM_BOT_TOKEN="<your_bot_token_here>"
```

3) Start the bot:

```bash
# simple run
ruby bot_spesa.rb

# or via bundler
bundle exec ruby bot_spesa.rb
```

4) Debug from VS Code

- Use the `.vscode/launch.json` configurations added to the workspace.
- Ensure `gem 'debug'` is installed (`bundle install`) and select the "Debug Bot (rdbg + bundler)" configuration.

Troubleshooting tips:
- If you get "Token not found" error, verify `TELEGRAM_BOT_TOKEN` or the `config` table in `spesa.db`.
- If a gem fails to install (native extension), install system deps (e.g., `libsqlite3-dev` on Debian/Ubuntu).
- To inspect the DB quickly, open `spesa.db` with the SQLite viewer extension or `sqlite3 spesa.db`.

Product scan rollback

The Open Food Facts/Yuka insertion flow does not change the database schema. To disable the server endpoint persistently:

```bash
sqlite3 "$HOME/termux-home/spesa/spesa.db" \
	"INSERT OR REPLACE INTO config (key, value) VALUES ('product_scan_enabled', 'false');"
```

Set the same key to `true` to enable it again. If the key is absent, the feature is enabled by default.

To build an APK with the previous insertion dialog and no product scan button:

```bash
cd apk
./gradlew assembleDebug -PPRODUCT_SCAN_ENABLED=false
```

Open Food Facts requires an identifying User-Agent. Configure it once in the existing `config` table on the production shell:

```bash
sqlite3 "$HOME/termux-home/spesa/spesa.db" \
	"INSERT OR REPLACE INTO config (key, value) VALUES ('open_food_facts_user_agent', 'BotSpesa/1.1 (contact@example.com)');"
```

Replace `contact@example.com` with a monitored contact address. The value persists across reboots and is read by the API server for every Open Food Facts request.

5) Production boot chain (Termux, versioned)

Keep boot logic versioned in this repo and deploy only symlinks to `.termux/boot`.

Versioned files:
- `termux_boot/start-services`
- `termux_boot/90-runit-guard.sh`
- `10-daze-start` should be owned by the Daze repository and linked from there.

Deploy links (run on production shell):

```bash
sh /data/data/com.termux/files/home/spesa/scripts/deploy_termux_boot_links.sh
```

If Daze is in a non-default path, set it explicitly:

```bash
DAZE_REPO_DIR=/data/data/com.termux/files/home/<daze-repo> sh /data/data/com.termux/files/home/spesa/scripts/deploy_termux_boot_links.sh
```

Notes:
- `.termux/boot` should contain symlinks to repo files, not ad-hoc copies.
- Backup files left executable in `.termux/boot` (for example `*.bak`) are unsafe because Termux:Boot may execute them too; the deploy script strips execute bits from common backup suffixes and warns about any other extra executable files.
- `start-services` is the canonical bootstrap.
- `90-runit-guard.sh` is additive and short-lived (default window: 90s), used to mitigate boot races.
- Duplicate `runsvdir` processes are filtered by matching the expected `SVDIR` argument, not by blindly keeping the first PID.
- `10-daze-start` should be symlinked to the Daze repository source file.
