"""Claude Code conversations for the phone remote (read-only).

User decision 2026-09-27 (on the PC): the phone may show the history of
Claude conversations — the current session and a list of all sessions.
Only message TEXTS are taken: the user's messages (typed on the PC or sent
from the phone) and Claude's answers. Tool calls, tool results, file
contents, thinking, attachments and system records are skipped. Reads only
~/.claude/projects/*/<session>.jsonl, nothing is written.

    python tools/claude_history.py sessions [limit]
        -> {"ok": true, "sessions": [{"id", "title", "folder", "updated"}]}
    python tools/claude_history.py read <session_id> [limit]
        -> {"ok": true, "id", "title", "messages": [{"role": "user"|"phone"|"assistant", "text", "time"}]}
"""
from __future__ import annotations

import json
import ntpath
import os
import re
import sys
from pathlib import Path

ROOT = Path.home() / '.claude' / 'projects'
SESSION_ID = re.compile(r'^[0-9a-fA-F-]{8,64}$')
PHONE_MARK = 'Сообщение от пользователя с телефона (пульт Хоши):'
MAX_MESSAGE = 4000
READ_BYTES = 24 * 1024 * 1024  # tail of the journal to read; tool results make it big


def _files() -> list[Path]:
    if not ROOT.is_dir():
        return []
    return [f for f in ROOT.glob('*/*.jsonl') if SESSION_ID.match(f.stem)]


def _tail_lines(path: Path, size: int) -> list[str]:
    with path.open('rb') as handle:
        handle.seek(0, os.SEEK_END)
        end = handle.tell()
        handle.seek(max(0, end - size))
        data = handle.read().decode('utf-8', errors='replace')
    lines = data.splitlines()
    return lines[1:] if end > size else lines  # the first line may be cut


def _title_and_folder(path: Path) -> tuple[str, str]:
    title, folder, first_prompt = '', '', ''
    for line in reversed(_tail_lines(path, 64 * 1024)):
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if not title and record.get('type') == 'custom-title':
            title = str(record.get('customTitle', ''))
        if not first_prompt and record.get('type') == 'last-prompt':
            first_prompt = str(record.get('lastPrompt', ''))
        if not folder and record.get('cwd'):
            folder = ntpath.basename(str(record['cwd']).rstrip('/\\'))
        if title and folder:
            break
    return (title or first_prompt or 'Без названия')[:80], folder[:80]


def sessions(limit: int = 30) -> list[dict]:
    files = sorted(_files(), key=lambda f: f.stat().st_mtime, reverse=True)[:limit]
    result = []
    for path in files:
        title, folder = _title_and_folder(path)
        result.append({'id': path.stem, 'title': title, 'folder': folder, 'updated': int(path.stat().st_mtime)})
    return result


def _text_of(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return '\n'.join(str(part.get('text', '')) for part in content
                         if isinstance(part, dict) and part.get('type') == 'text')
    return ''


def message_of(record: dict) -> dict | None:
    """Pure: one transcript record -> a chat message, or None (skipped)."""
    kind = record.get('type')
    message = record.get('message') or {}
    if kind == 'assistant':
        text = _text_of(message.get('content')).strip()
        return {'role': 'assistant', 'text': text} if text else None
    if kind != 'user' or record.get('isMeta'):
        return None
    content = message.get('content')
    if isinstance(content, list) and any(isinstance(p, dict) and p.get('type') == 'tool_result' for p in content):
        return None
    text = _text_of(content)
    origin = (record.get('origin') or {}).get('kind', 'human')
    if PHONE_MARK in text:
        text = text.split(PHONE_MARK, 1)[1].split('</system-reminder>', 1)[0].strip()
        return {'role': 'phone', 'text': text} if text else None
    if origin != 'human':
        return None
    text = text.strip()
    if not text or text.startswith('<'):
        return None
    return {'role': 'user', 'text': text}


def read(session_id: str, limit: int = 60) -> dict:
    if not SESSION_ID.match(session_id):
        return {'ok': False, 'error': 'bad_id'}
    path = next((f for f in _files() if f.stem == session_id), None)
    if path is None:
        return {'ok': False, 'error': 'no_session'}
    messages: list[dict] = []
    for line in _tail_lines(path, READ_BYTES):
        try:
            record = json.loads(line)
        except ValueError:
            continue
        item = message_of(record)
        if item is None:
            continue
        item['text'] = item['text'][:MAX_MESSAGE]
        item['time'] = str(record.get('timestamp', ''))[:19]
        # Claude's answer comes in several records in a row: glue them together.
        if messages and item['role'] == 'assistant' and messages[-1]['role'] == 'assistant':
            messages[-1]['text'] = (messages[-1]['text'] + '\n\n' + item['text'])[:MAX_MESSAGE]
            continue
        messages.append(item)
    title, _ = _title_and_folder(path)
    return {'ok': True, 'id': session_id, 'title': title, 'messages': messages[-limit:]}


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding='utf-8')
    if len(argv) in (2, 3) and argv[1] == 'sessions':
        print(json.dumps({'ok': True, 'sessions': sessions(int(argv[2]) if len(argv) == 3 and argv[2].isdigit() else 30)}, ensure_ascii=False))
        return 0
    if len(argv) in (3, 4) and argv[1] == 'read':
        print(json.dumps(read(argv[2], int(argv[3]) if len(argv) == 4 and argv[3].isdigit() else 60), ensure_ascii=False))
        return 0
    print('usage: claude_history.py sessions [limit] | read <session_id> [limit]', file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
