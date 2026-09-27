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

With --ask (synchronous hooks: PermissionRequest, and PreToolUse for
AskUserQuestion; user decision 2026-09-27) Claude's permission requests and
multiple-choice questions go to the phone while a phone is connected. Hoshi
answers at once "no phone" -> nothing is printed and the usual dialog shows on
the PC. A phone answer comes back as the hook decision (allow/deny, or the
chosen answers). No answer in ASK_WAIT seconds -> the usual dialog on the PC.

Media (user request 2026-09-27): pictures, GIFs and videos that the answer
itself names (absolute path, or relative to the session folder) are listed
for Hoshi so the phone can view them. Only existing media files up to 16 MB,
at most 8. The full path goes to Hoshi on this PC only, never to the phone.
"""
from __future__ import annotations

import http.client
import json
import ntpath
import os
import re
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
ASK_WAIT = 32.0  # Hoshi lets go after 30 s; a little longer here
EVENTS = {'SessionStart', 'UserPromptSubmit', 'Notification', 'Stop', 'SessionEnd'}
MEDIA_KINDS = {'.png': 'image', '.jpg': 'image', '.jpeg': 'image', '.gif': 'image', '.webp': 'image',
               '.mp4': 'video', '.webm': 'video'}
MAX_MEDIA = 8
MAX_MEDIA_BYTES = 16 * 1024 * 1024
# Candidates: markdown link targets, `code` spans, and bare Windows/relative paths ending in a media extension.
_EXT = r'\.(?:png|jpe?g|gif|webp|mp4|webm)'
_CANDIDATES = [
    re.compile(r'\]\(([^)\s]+)\)'),
    re.compile(r'`([^`\n]+)`'),
    re.compile(r'((?:[A-Za-z]:)?[\w.\-\\/~]*' + _EXT + r')', re.IGNORECASE),
]


def media_in(text: str, cwd: str) -> list[dict]:
    """Media files the answer names: [{path, name, kind}] (existing, small enough)."""
    found: list[dict] = []
    seen: set[str] = set()
    for pattern in _CANDIDATES:
        for match in pattern.finditer(text):
            raw = match.group(1).strip().strip('"\'<>').split('#')[0].split('?')[0]
            kind = MEDIA_KINDS.get(os.path.splitext(raw)[1].lower())
            # Never network paths: "//host/x.png" or "\\host\x.png" (also cut out of URLs)
            # would make Windows contact another computer.
            if not kind or raw.lower().startswith(('http://', 'https://')) or raw[:2] in ('//', '\\\\', '/\\', '\\/'):
                continue
            path = raw if os.path.isabs(raw) else os.path.join(cwd, raw)
            if path[:2] in ('//', '\\\\', '/\\', '\\/'):
                continue
            try:
                path = os.path.realpath(path)
                if path[:2] in ('//', '\\\\'):
                    continue
                if path.lower() in seen or not os.path.isfile(path) or os.path.getsize(path) > MAX_MEDIA_BYTES:
                    continue
            except OSError:
                continue
            seen.add(path.lower())
            found.append({'path': path, 'name': os.path.basename(path)[:80], 'kind': kind})
            if len(found) >= MAX_MEDIA:
                return found
    return found


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
        message['media'] = media_in(message['text'], str(event.get('cwd', '')))
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
                       'text': str(event.get('last_assistant_message', ''))[:MAX_TEXT],
                       'media': media_in(str(event.get('last_assistant_message', ''))[:MAX_TEXT], str(event.get('cwd', '')))},
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


def _short(value, limit: int = 400) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return text[:limit]


def ask_message(event: dict) -> dict | None:
    """What to show on the phone for a permission request or a question."""
    name = str(event.get('hook_event_name', ''))
    tool = str(event.get('tool_name', ''))[:60]
    tool_input = event.get('tool_input', {}) if isinstance(event.get('tool_input'), dict) else {}
    base = {'app': 'claude', 'session': str(event.get('session_id', ''))[:64],
            'folder': ntpath.basename(str(event.get('cwd', '')).rstrip('/\\'))[:80]}
    if name == 'PreToolUse' and tool == 'AskUserQuestion':
        questions = []
        for q in (tool_input.get('questions') or [])[:4]:
            if not isinstance(q, dict):
                continue
            options = [{'label': _short(o.get('label', ''), 80), 'description': _short(o.get('description', ''), 200)}
                       for o in (q.get('options') or [])[:6] if isinstance(o, dict)]
            questions.append({'question': _short(q.get('question', ''), 400), 'header': _short(q.get('header', ''), 30),
                              'multiSelect': bool(q.get('multiSelect', False)), 'options': options})
        return dict(base, event='Question', questions=questions) if questions else None
    if name == 'PermissionRequest':
        # The gist of what Claude wants to do: a command, a file, a site.
        detail = tool_input.get('command') or tool_input.get('file_path') or tool_input.get('url') or tool_input.get('pattern') or tool_input
        return dict(base, event='Permission', tool=tool, detail=_short(detail, 600))
    return None


def ask_phone(event: dict) -> int:
    """--ask: hold the question until the phone answers (or Hoshi lets go)."""
    message = ask_message(event)
    if message is None or not message['session']:
        return 0
    connection = http.client.HTTPConnection(HOST, PORT, timeout=ASK_WAIT)
    try:
        connection.request('POST', PATH, json.dumps(message, ensure_ascii=False).encode('utf-8'), {'Content-Type': 'application/json'})
        answer = connection.getresponse()
        status, data = answer.status, answer.read()
    except OSError:
        return 0  # Hoshi closed or no answer in time: the usual dialog on the PC
    finally:
        connection.close()
    if status != 200:
        return 0
    try:
        reply = json.loads(data.decode('utf-8'))
    except ValueError:
        return 0
    if message['event'] == 'Permission' and reply.get('behavior') in ('allow', 'deny'):
        decision = {'behavior': reply['behavior']}
        if reply['behavior'] == 'deny':
            decision['message'] = 'Запрещено с телефона (пульт Хоши)'
        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': decision}}, ensure_ascii=False))
        return 0
    if message['event'] == 'Question' and isinstance(reply.get('answers'), dict):
        tool_input = dict(event.get('tool_input') or {})
        known = {q['question'] for q in message['questions']}
        tool_input['answers'] = {str(k): str(v)[:500] for k, v in reply['answers'].items() if str(k) in known}
        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow',
                                                 'permissionDecisionReason': 'Ответ с телефона (пульт Хоши)',
                                                 'updatedInput': tool_input}}, ensure_ascii=False))
        return 0
    return 0


def main() -> int:
    try:
        event = json.loads(sys.stdin.buffer.read().decode('utf-8', errors='replace') or '{}')
    except ValueError:
        return 0
    if not isinstance(event, dict):
        return 0
    if '--wait' in sys.argv[1:]:
        return wait_for_phone(event) if event.get('hook_event_name') == 'Stop' else 0
    if '--ask' in sys.argv[1:]:
        sys.stdout.reconfigure(encoding='utf-8')
        return ask_phone(event)
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
