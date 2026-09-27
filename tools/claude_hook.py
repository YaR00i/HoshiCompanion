"""Claude Code hook -> Hoshi: "Claude is working / done / waiting" (+ last answer).

Installed as an async command hook in the user's Claude Code settings
(~/.claude/settings.json, all projects; user decision 2026-09-27) for
SessionStart, UserPromptSubmit, Notification, Stop and SessionEnd.
Claude Code passes the event JSON on stdin; this script keeps only what the
user allowed (event, session id, project FOLDER NAME, notification type/text,
text of the last answer) and posts it to Hoshi on this PC only
(http://127.0.0.1:18772/assistant). Hoshi is closed -> it silently does nothing,
so Claude never waits and never sees errors.

With --wait (a separate Stop hook, "asyncRewake": true) it waits in the
background for a reply typed on the phone and wakes Claude with it
(user decision 2026-09-27: write to Claude from the phone).
"""
from __future__ import annotations

import http.client
import json
import ntpath
import sys
import time
import urllib.request

HOST = '127.0.0.1'
PORT = 18772
PATH = '/assistant'
URL = 'http://%s:%d%s' % (HOST, PORT, PATH)
# --wait: Hoshi went away while we waited (restart) -> knock every few seconds, for a while.
RETRY_EVERY = 3.0
RETRY_AFTER_LOSS = 12 * 3600.0  # Hoshi closed for the night -> the card comes back in the morning
MAX_TEXT = 6000
EVENTS = {'SessionStart', 'UserPromptSubmit', 'Notification', 'Stop', 'SessionEnd'}


def clean(event: dict) -> dict | None:
    name = str(event.get('hook_event_name', ''))
    session = str(event.get('session_id', ''))[:64]
    if name not in EVENTS or not session:
        return None
    message = {
        'app': 'claude',
        'event': name,
        'session': session,
        # Folder name only (e.g. "HoshiCompanion"), never the full path.
        'folder': ntpath.basename(str(event.get('cwd', '')).rstrip('/\\'))[:80],
    }
    if name == 'Notification':
        message['kind'] = str(event.get('notification_type', ''))[:40]
        message['text'] = str(event.get('notification_message', ''))[:300]
    elif name == 'Stop':
        message['text'] = str(event.get('last_assistant_message', ''))[:MAX_TEXT]
    return message


def wait_for_phone(event: dict) -> int:
    """--wait (Stop hook with asyncRewake): wait for a reply typed on the phone.

    Hoshi keeps this request open. A reply arrives -> print it and exit 2, so
    Claude Code wakes Claude with it. The user typed on the PC or the session
    ended -> exit 0 quietly. Hoshi is not running -> exit 0 at once.
    Hoshi was running and went away (restart, closed for the night) -> knock
    again every few seconds for up to 12 hours; each knock also brings back
    the last answer, so the phone card reappears without Hoshi writing
    anything to disk.
    """
    session = str(event.get('session_id', ''))[:64]
    if not session:
        return 0
    body = json.dumps({'app': 'claude', 'event': 'Wait', 'session': session,
                       'folder': ntpath.basename(str(event.get('cwd', '')).rstrip('/\\'))[:80],
                       'text': str(event.get('last_assistant_message', ''))[:MAX_TEXT]},
                      ensure_ascii=False).encode('utf-8')
    lost_at = 0.0
    while True:
        connection = http.client.HTTPConnection(HOST, PORT, timeout=None)
        try:
            connection.connect()
        except OSError:
            # Never reached Hoshi, or she has not come back after a restart in time.
            if lost_at == 0.0 or time.monotonic() - lost_at > RETRY_AFTER_LOSS:
                return 0
            time.sleep(RETRY_EVERY)
            continue
        try:
            # No timeout: Hoshi answers when the phone replies or lets go.
            connection.request('POST', PATH, body, {'Content-Type': 'application/json'})
            answer = connection.getresponse()
            status, data = answer.status, answer.read()
        except OSError:
            lost_at = time.monotonic()  # Hoshi closed while we waited: maybe a restart
            time.sleep(RETRY_EVERY)
            continue
        finally:
            connection.close()
        if status != 200:
            return 0
        try:
            text = str(json.loads(data.decode('utf-8')).get('text', '')).strip()[:2000]
        except ValueError:
            return 0
        break
    if not text:
        return 0
    sys.stderr.buffer.write(('Сообщение от пользователя с телефона (пульт Хоши):\n' + text + '\n').encode('utf-8'))
    sys.stderr.flush()
    return 2


def main() -> int:
    try:
        event = json.loads(sys.stdin.buffer.read().decode('utf-8', errors='replace') or '{}')
    except ValueError:
        return 0
    if not isinstance(event, dict):
        return 0
    if '--wait' in sys.argv[1:]:
        return wait_for_phone(event) if event.get('hook_event_name') == 'Stop' else 0
    message = clean(event)
    if message is None:
        return 0
    request = urllib.request.Request(URL, data=json.dumps(message, ensure_ascii=False).encode('utf-8'),
                                     headers={'Content-Type': 'application/json'}, method='POST')
    try:
        # No system proxy (a VPN may set one): this goes to this PC only.
        urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=1.0).close()
    except OSError:
        pass  # Hoshi is not running: nothing to tell.
    return 0


if __name__ == '__main__':
    sys.exit(main())
