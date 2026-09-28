"""Read-only Codex conversation texts for Hoshi's paired phone.

The rollout JSONL format is not a stable Codex API. This reader only accepts
known message records and skips tool calls/results, reasoning, instructions,
attachments, and non-final assistant messages.
"""
from __future__ import annotations

import json
import ntpath
import os
import re
import sys
from pathlib import Path

ROOT = Path.home() / '.codex' / 'sessions'
SESSION_ID = re.compile(r'^[0-9a-fA-F-]{8,64}$')
PHONE_MARK = 'Сообщение от пользователя с телефона (пульт Хоши):'
MAX_MESSAGE = 4000
READ_BYTES = 24 * 1024 * 1024


def _files() -> list[Path]:
    return list(ROOT.glob('*/*/*/rollout-*.jsonl')) if ROOT.is_dir() else []


def _tail_lines(path: Path, size: int) -> list[str]:
    with path.open('rb') as handle:
        handle.seek(0, os.SEEK_END)
        end = handle.tell()
        handle.seek(max(0, end - size))
        data = handle.read().decode('utf-8', errors='replace')
    lines = data.splitlines()
    return lines[1:] if end > size else lines


def _id(path: Path) -> str:
    # Current filenames end with the session id; some carry another id before it.
    match = re.search(r'([0-9a-fA-F]{8}-[0-9a-fA-F-]{20,55})$', path.stem)
    return match.group(1) if match else ''


def _text(content, role: str) -> str:
    if not isinstance(content, list):
        return ''
    expected = 'output_text' if role == 'assistant' else 'input_text'
    return '\n'.join(part.get('text', '') for part in content
                     if isinstance(part, dict) and part.get('type') == expected
                     and isinstance(part.get('text'), str))


def message_of(record: dict) -> dict | None:
    if record.get('type') != 'response_item':
        return None
    payload = record.get('payload')
    if not isinstance(payload, dict) or payload.get('type') != 'message':
        return None
    role = payload.get('role')
    if role not in ('user', 'assistant'):
        return None
    if role == 'assistant' and payload.get('phase') not in (None, 'final', 'final_answer'):
        return None
    text = _text(payload.get('content'), role).strip()
    if not text:
        return None
    if role == 'user' and PHONE_MARK in text:
        text = text.split(PHONE_MARK, 1)[1].strip()
        role = 'phone'
    return {'role': role, 'text': text} if text else None


def _metadata(path: Path) -> tuple[str, str, str]:
    session_id, folder, title = _id(path), '', ''
    with path.open('r', encoding='utf-8', errors='replace') as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get('type') == 'session_meta':
                payload = record.get('payload') or {}
                session_id = str(payload.get('id') or payload.get('session_id') or session_id)
                folder = ntpath.basename(str(payload.get('cwd') or '').rstrip('/\\'))[:80]
            if not title:
                message = message_of(record)
                if message and message['role'] in ('user', 'phone'):
                    title = message['text'].splitlines()[0][:80]
            if folder and title:
                break
    return session_id, folder, title or 'Без названия'


def sessions(limit: int = 30) -> list[dict]:
    result = []
    for path in sorted(_files(), key=lambda f: f.stat().st_mtime, reverse=True)[:max(0, min(limit, 30))]:
        try:
            session_id, folder, title = _metadata(path)
            if SESSION_ID.fullmatch(session_id):
                result.append({'id': session_id, 'folder': folder, 'title': title,
                               'updated': int(path.stat().st_mtime)})
        except OSError:
            continue
    return result


def read(session_id: str, limit: int = 50) -> dict:
    if not SESSION_ID.fullmatch(session_id):
        return {'ok': False, 'error': 'bad_id'}
    path = next((f for f in _files() if f.stem.endswith(session_id)), None)
    if path is None:
        return {'ok': False, 'error': 'no_session'}
    try:
        found_id, _, title = _metadata(path)
        if found_id != session_id:
            return {'ok': False, 'error': 'no_session'}
        messages = []
        for line in _tail_lines(path, READ_BYTES):
            try:
                record = json.loads(line)
            except ValueError:
                continue
            message = message_of(record)
            if message is None:
                continue
            message['text'] = message['text'][:MAX_MESSAGE]
            message['time'] = str(record.get('timestamp', ''))[:19]
            messages.append(message)
        return {'ok': True, 'id': session_id, 'title': title, 'messages': messages[-max(0, min(limit, 50)):]}
    except OSError:
        return {'ok': False, 'error': 'unreadable'}


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding='utf-8')
    if len(argv) in (2, 3) and argv[1] == 'sessions':
        print(json.dumps({'ok': True, 'sessions': sessions(int(argv[2]) if len(argv) == 3 and argv[2].isdigit() else 30)}, ensure_ascii=False))
        return 0
    if len(argv) in (3, 4) and argv[1] == 'read':
        print(json.dumps(read(argv[2], int(argv[3]) if len(argv) == 4 and argv[3].isdigit() else 50), ensure_ascii=False))
        return 0
    return 2


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
