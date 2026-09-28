"""Codex lifecycle hook for Hoshi's local phone remote.

Only the session id, project folder name, status, final answer, and media named
in that answer reach Hoshi. The transcript path stays on this PC. Stop waits
for at most 60 seconds while a paired phone is connected, then lets Codex end.
"""
from __future__ import annotations

import http.client
import json
import ntpath
import os
import sys
import time

from claude_hook import media_in

HOST = '127.0.0.1'
PORT = 18772
PATH = '/assistant'
MAX_TEXT = 6000
WAIT_SECONDS = 65  # Hoshi releases the waiter after 60 seconds.
ASK_SECONDS = 32
PHONE_MARK = 'Сообщение от пользователя с телефона (пульт Хоши):'
LOG_LIMIT = 200 * 1024
EVENTS = {'SessionStart', 'UserPromptSubmit', 'Stop', 'Interrupt', 'SessionEnd'}


def log(event: str, session: str, outcome: str) -> None:
    """Small diagnostic record with no prompts, answers, paths or tool input."""
    try:
        folder = os.path.join(os.environ.get('LOCALAPPDATA', os.path.expanduser('~')), 'HoshiCompanion')
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, 'codex_hook.log')
        if os.path.exists(path) and os.path.getsize(path) > LOG_LIMIT:
            os.replace(path, path + '.old')
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write('%s %s %s %s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), event[:20], session[:8], outcome[:40]))
    except OSError:
        pass


def clean(event: dict) -> dict | None:
    name = str(event.get('hook_event_name', ''))
    session = str(event.get('session_id', ''))[:64]
    if name not in EVENTS or not session:
        return None
    message = {'app': 'codex', 'event': name, 'session': session,
               'folder': ntpath.basename(str(event.get('cwd', '')).rstrip('/\\'))[:80]}
    transcript = event.get('transcript_path')
    if isinstance(transcript, str) and os.path.isabs(transcript) and transcript.endswith('.jsonl'):
        message['transcript_path'] = transcript
    if name == 'Stop':
        message['text'] = str(event.get('last_assistant_message') or '')[:MAX_TEXT]
        message['media'] = media_in(message['text'], str(event.get('cwd', '')))
    return message


def post(message: dict, timeout: float = 2) -> tuple[int, bytes]:
    connection = http.client.HTTPConnection(HOST, PORT, timeout=timeout)
    try:
        connection.request('POST', PATH, json.dumps(message, ensure_ascii=False).encode('utf-8'),
                           {'Content-Type': 'application/json'})
        answer = connection.getresponse()
        return answer.status, answer.read()
    finally:
        connection.close()


def stop(event: dict, message: dict) -> None:
    session = message['session']
    try:
        post(message)
    except OSError:
        log('Stop', session, 'no Hoshi')
        print('{}')
        return
    waiter = dict(message, event='Wait')
    try:
        status, data = post(waiter, WAIT_SECONDS)
    except OSError:
        log('Stop', session, 'wait ended')
        print('{}')
        return
    if status == 200:
        try:
            text = str(json.loads(data.decode('utf-8')).get('text', '')).strip()[:2000]
        except (ValueError, AttributeError):
            text = ''
        if text:
            log('Stop', session, 'phone reply')
            print(json.dumps({'decision': 'block', 'reason': PHONE_MARK + '\n' + text}, ensure_ascii=False))
            return
    log('Stop', session, 'done')
    print('{}')


def permission(event: dict) -> None:
    session = str(event.get('session_id', ''))[:64]
    if not session:
        print('{}')
        return
    tool_input = event.get('tool_input') if isinstance(event.get('tool_input'), dict) else {}
    detail = tool_input.get('description') or tool_input.get('command') or tool_input.get('file_path') or tool_input.get('url') or ''
    message = {'app': 'codex', 'event': 'Permission', 'session': session,
               'folder': ntpath.basename(str(event.get('cwd', '')).rstrip('/\\'))[:80],
               'transcript_path': event.get('transcript_path') or '',
               'tool': str(event.get('tool_name', ''))[:60], 'detail': str(detail)[:600]}
    try:
        status, data = post(message, ASK_SECONDS)
    except OSError:
        print('{}')
        return
    if status == 200:
        try:
            behavior = json.loads(data.decode('utf-8')).get('behavior')
        except (ValueError, AttributeError):
            behavior = None
        if behavior in ('allow', 'deny'):
            decision = {'behavior': behavior}
            if behavior == 'deny':
                decision['message'] = 'Запрещено с телефона (пульт Хоши)'
            print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': decision}}, ensure_ascii=False))
            return
    print('{}')


def main() -> int:
    try:
        event = json.loads(sys.stdin.buffer.read().decode('utf-8', errors='replace') or '{}')
    except ValueError:
        event = {}
    if not isinstance(event, dict):
        event = {}
    if event.get('hook_event_name') == 'PermissionRequest':
        permission(event)
        return 0
    message = clean(event)
    if message is None:
        return 0
    if message['event'] == 'Stop':
        stop(event, message)
    else:
        try:
            post(message)
        except OSError:
            pass  # Hoshi is closed; Codex continues normally.
        if message['event'] == 'Interrupt':
            print('{}')  # Interrupt expects JSON; its output cannot restart the turn.
    return 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main())
