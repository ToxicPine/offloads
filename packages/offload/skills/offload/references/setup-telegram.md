# Connect the machine to Telegram

This is optional. Do it once per machine when the user wants either feature:

- **Progress pings while offloaded work runs.** `nix run github:ToxicPine/offloads#vusperize -- --deliver telegram`
  sends updates to a Telegram chat.
- **Phone access to the agent on the machine.** The user can message the Telegram bot instead of
  staying at a terminal.

Telegram bot setup is free. The bot token is a password. Treat it as secret and confirm before saving
it.

## Plain Model

A Telegram bot is a Telegram account controlled by a program. The user creates the bot and receives
a long password called a **token**. Save that token on the machine, then list the Telegram user IDs
allowed to talk to it, and configure Hermes through `offloader-configurator` using the
`hermes setup --portal` account flow. After that, progress pings and agent replies appear as messages
from the bot.

This does not change the user's normal Telegram account. It only lets that account receive messages
from and chat with the new bot.

## 1. Make the bot

The user creates the bot by talking to Telegram's official bot maker:

1. Open Telegram and search for **@BotFather** (or open https://t.me/BotFather).
2. Send `/newbot`.
3. Pick a display name (anything, e.g. "My Offloader Agent").
4. Pick a username — it has to be unique and end in `bot` (e.g. `my_offload_bot`).
5. BotFather replies with the **token**, which looks like `123456789:ABCdef...`.

The token is the bot's password. If it leaks, the user can revoke it with `/revoke` in BotFather and
make a new one.

## 2. Get the user's Telegram ID

The machine allows users by numeric Telegram user ID, such as `123456789`, **not** by `@username`.
The easiest way to find it: in Telegram, message
**@userinfobot** (https://t.me/userinfobot) and it replies with the ID. Save that number.

If more than one person should be allowed, collect each of their IDs.

## 3. Give the machine the token and the allowed users

These are secrets the *machine itself* needs, so store them as Fly app secrets, never in a project:

```bash
<offload-nix> fly secrets set -a <app> TELEGRAM_BOT_TOKEN=<token>
<offload-nix> fly secrets set -a <app> TELEGRAM_ALLOWED_USERS=<id>
```

`TELEGRAM_ALLOWED_USERS` takes a comma-separated list when more than one person is allowed, e.g.
`111111111,222222222`.

Optionally, set a "home" chat. This is where the agent sends messages it starts, such as scheduled
results or `vusperize` pings when no chat is passed. For a normal one-on-one chat with the bot, use
the user's Telegram ID:

```bash
<offload-nix> fly secrets set -a <app> TELEGRAM_HOME_CHANNEL=<id>
```

## 4. Configure Hermes

Progress pings and Telegram chat both need the Hermes account configured with
`offloader-configurator`:

```bash
if [ -z "${OFFLOADER_TRANSPORT:-}" ] && [ -r "$HOME/.offload-skill-transport" ]; then
  . "$HOME/.offload-skill-transport"
fi
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader-configurator -- --transport "$OFFLOADER_TRANSPORT" hermes account check
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader-configurator -- --transport "$OFFLOADER_TRANSPORT" hermes account configure
```

This should follow Hermes' standard `hermes setup --portal` flow, where one OAuth sets up the model
account and Tool Gateway tools. If the user wants to reuse a Codex subscription, that choice belongs
inside this Hermes account flow.

## 5. Check it works

The agent on the machine reads these settings when its gateway runs. Have the user open Telegram,
find the new bot by username, and send it a message. It should answer within a few seconds.

If it stays silent, check the common causes:

- The token was mistyped.
- The user's numeric ID is missing from `TELEGRAM_ALLOWED_USERS`.
- The Hermes account is not configured.
- The gateway was already running and has not read the new secrets yet. `fly secrets set` usually
  restarts Machines; if needed, check with `<offload-nix> fly status -a <app>` and restart through
  Fly.

## Using it for offload progress pings

Once Telegram is connected, wrap a long remote command with `vusperize`:

```bash
<skill-dir>/scripts/nix run github:ToxicPine/offloads#offloader -- -- bash -lc 'nix run github:ToxicPine/offloads#vusperize -- --deliver telegram -- <long command>'
```

If `TELEGRAM_HOME_CHANNEL` is set, pings go there automatically. To send them to a specific chat,
add `--deliver-chat-id <id>`. For a one-on-one chat with the bot, that ID is the user's own Telegram
ID.

## Where these settings live

The bot token, allowed users, home chat, and Hermes account belong to the *machine*. Keep bot secrets
in Fly app secrets with `<offload-nix> fly secrets set -a <app> ...`, out of every project. Machine
credentials stay with the machine. Project-specific settings stay with the project.
