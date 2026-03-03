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
