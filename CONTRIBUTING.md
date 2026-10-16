# Contributing

Mostly this means adding entries to the files in `data/`.

- `data/defaults.txt`: `category|domain|key|type|value|description`. Type is `bool`, `int` or `string`. Check the key on a real Mac with `defaults read <domain> <key>` before sending it, and mention which macOS version you tried it on.
- `data/agents.txt`: `category|launchd label|description`.
- `data/apps.txt`: `category|App.app|description`. Only apps that can be deleted normally.

Keep the code bash 3.2 compatible, since that's what macOS has. That means no associative arrays, no `mapfile`, no `${var,,}`. `tests/smoke.sh` greps for the common ones.

Before sending a change: `bash tests/smoke.sh && bash tests/test_stubbed.sh`.
