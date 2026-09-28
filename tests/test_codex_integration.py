"""Privacy and reply-contract checks for the Codex phone bridge."""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import codex_history  # noqa: E402
import codex_hook  # noqa: E402


class CodexIntegrationTests(unittest.TestCase):
    def test_hook_sends_only_allowed_fields_and_phone_reply_continues(self) -> None:
        event = {'hook_event_name': 'Stop', 'session_id': '01234567-89ab-cdef-0123-456789abcdef',
                 'cwd': r'D:\projects\HoshiCompanion', 'last_assistant_message': 'Готово',
                 'prompt': 'PRIVATE PROMPT', 'tool_input': {'command': 'PRIVATE TOOL'},
                 'transcript_path': r'C:\Users\test\.codex\sessions\x.jsonl'}
        message = codex_hook.clean(event)
        self.assertEqual(message['folder'], 'HoshiCompanion')
        self.assertNotIn('PRIVATE', json.dumps(message))
        interrupted = codex_hook.clean(dict(event, hook_event_name='Interrupt'))
        self.assertEqual(interrupted['event'], 'Interrupt')
        self.assertNotIn('text', interrupted)
        output = io.StringIO()
        with patch.object(codex_hook, 'post', side_effect=[(204, b''), (200, json.dumps({'text': 'Продолжай'}).encode('utf-8'))]), \
             patch.object(codex_hook, 'log'), contextlib.redirect_stdout(output):
            codex_hook.stop(event, message)
        self.assertEqual(json.loads(output.getvalue())['decision'], 'block')
        self.assertIn('Продолжай', json.loads(output.getvalue())['reason'])

    def test_history_excludes_internal_records(self) -> None:
        def record(kind: str, role: str = '', content: str = '', phase: str = '') -> dict:
            payload = {'type': kind, 'role': role, 'content': [{'type': 'output_text' if role == 'assistant' else 'input_text', 'text': content}]}
            if phase:
                payload['phase'] = phase
            return {'type': 'response_item', 'payload': payload}
        self.assertIsNone(codex_history.message_of(record('reasoning', 'assistant', 'SECRET')))
        self.assertIsNone(codex_history.message_of(record('custom_tool_call_output', 'assistant', 'SECRET')))
        self.assertIsNone(codex_history.message_of(record('message', 'developer', 'SECRET')))
        self.assertIsNone(codex_history.message_of(record('message', 'assistant', 'working...', 'commentary')))
        self.assertEqual(codex_history.message_of(record('message', 'assistant', 'Готово', 'final_answer'))['text'], 'Готово')
        phone = codex_history.message_of(record('message', 'user', codex_history.PHONE_MARK + '\nПродолжай'))
        self.assertEqual(phone, {'role': 'phone', 'text': 'Продолжай'})

    def test_history_reads_only_selected_session_messages(self) -> None:
        session_id = '01234567-89ab-cdef-0123-456789abcdef'
        with tempfile.TemporaryDirectory() as root, patch.object(codex_history, 'ROOT', Path(root)):
            folder = Path(root) / '2026' / '09' / '28'
            folder.mkdir(parents=True)
            path = folder / ('rollout-2026-09-28T12-00-00-' + session_id + '.jsonl')
            records = [
                {'type': 'session_meta', 'payload': {'id': session_id, 'cwd': r'D:\projects\HoshiCompanion'}},
                {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user', 'content': [{'type': 'input_text', 'text': 'Привет'}]}},
                {'type': 'response_item', 'payload': {'type': 'function_call_output', 'output': 'SECRET TOOL'}},
                {'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant', 'phase': 'final', 'content': [{'type': 'output_text', 'text': 'Здравствуй'}]}},
            ]
            path.write_text('\n'.join(json.dumps(r, ensure_ascii=False) for r in records), encoding='utf-8')
            self.assertEqual([m['text'] for m in codex_history.read(session_id)['messages']], ['Привет', 'Здравствуй'])
            self.assertEqual(codex_history.sessions()[0]['folder'], 'HoshiCompanion')
            self.assertFalse(codex_history.read('../secret')['ok'])


if __name__ == '__main__':
    unittest.main()
