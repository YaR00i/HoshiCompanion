"""Checks browser_extension/hoshi_apps/youtube.js on a fake YouTube page (no network).

Optional dev check: needs `pip install playwright` + a Chromium for Playwright.
Run: python tests/extension/test_youtube_content.py
"""
from __future__ import annotations

import functools
import http.server
import json
from pathlib import Path
import threading

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
PAGE = (Path(__file__).with_name('fake_youtube.html')).read_bytes()
HOME = (Path(__file__).with_name('fake_youtube_home.html')).read_bytes()
SCRIPT = (ROOT / 'browser_extension' / 'hoshi_apps' / 'youtube.js').read_text(encoding='utf-8')

STUB = """
window.__sent = [];
window.chrome = { runtime: { connect() {
  const listeners = [];
  const port = {
    postMessage: (m) => window.__sent.push(JSON.parse(JSON.stringify(m))),
    onMessage: { addListener: (f) => listeners.push(f) },
    onDisconnect: { addListener: () => {} },
  };
  window.__deliver = (m) => listeners.forEach((f) => f(m));
  return port;
} } };
"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(HOME if self.path == '/' else PAGE)

    def log_message(self, *args):
        pass


def main() -> None:
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 18799), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    checks = failures = 0

    def check(ok: bool, label: str) -> None:
        nonlocal checks, failures
        checks += 1
        if not ok:
            failures += 1
        print(('PASS: ' if ok else 'FAIL: ') + label)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        page.add_init_script(STUB)
        page.goto('http://127.0.0.1:18799/watch?v=abcDEF12345&list=PLhoshi')
        page.add_script_tag(content=SCRIPT)
        page.wait_for_timeout(300)
        state = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        check(state['title'] == 'Lo-fi для рисования — 1 час' and state['subtitle'] == 'Hoshi Radio', 'reads title and channel')
        check(state['time'] == 42 and state['duration'] == 3600 and state['playing'] is False, 'reads time and pause')
        check(state['thumbnail'].endswith('/abcDEF12345/mqdefault.jpg') and state['icons']['toggle'] == '▶', 'thumbnail and play icon')
        lists = {item['id']: item for item in state.get('lists', [])}
        nxt = lists.get('next', {}).get('items', [])
        check([i['id'] for i in nxt[:2]] == ['nextAAA1111', 'nextBBB2222'] and len(nxt) == 20,
              'all loaded recommendations below the video are collected once each')
        check(nxt and nxt[1]['title'] == 'Как рисовать аниме-глаза' and nxt[1]['thumbnail'].endswith('/nextBBB2222/mqdefault.jpg'), 'up-next items have titles and covers (new YouTube layout too)')
        pl = lists.get('playlist', {})
        check(pl.get('title') == 'Плейлист · Музыка для работы' and pl.get('position') == '2 / 3', 'playlist title and position')
        check([i['current'] for i in pl.get('items', [])] == [False, True, False] and pl['items'][2]['list'] == 'PLhoshi', 'current playlist video is marked')
        run = lambda command, args=None: page.evaluate('([c, a]) => window.__deliver({op: "run", command: c, args: a || {}})', [command, args])
        run('toggle'); page.wait_for_timeout(250)
        check(page.evaluate('!window.__v.paused'), 'toggle starts playback')
        last = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        check(last['playing'] is True and last['icons']['toggle'] == '⏸', 'state follows playback')
        run('forward', {'seconds': 10}); run('back', {'seconds': 30})
        check(page.evaluate('window.__v.currentTime') == 22, 'seek forward and back')
        run('seek_to', {'time': 1800})
        check(page.evaluate('window.__v.currentTime') == 1800, 'seek to a moment from the progress bar')
        run('vol_up'); run('vol_up')
        check(abs(page.evaluate('window.__v.volume') - 0.7) < 1e-6, 'volume up')
        run('mute')
        check(page.evaluate('window.__v.muted') is True, 'mute presses the player button')
        run('next')
        check(page.evaluate('window.__nextClicks') == 1, 'next presses the player button')
        run('like'); page.wait_for_timeout(900)
        check(page.evaluate('document.querySelector("like-button-view-model button").getAttribute("aria-pressed")') == 'true', 'like presses the like button')
        check(page.evaluate('window.__sent.some(m => m.op === "event" && m.event === "liked")'), 'like is reported as an event for Hoshi')
        last = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        check('like' in last['active'] and 'mute' in last['active'], 'phone can highlight like and mute')
        check(page.evaluate('window.__hoshiYouTube.run("rm -rf", {})') is False, 'unknown commands do nothing')
        run('play_item', {'id': 'listCCC0003', 'list': 'PLhoshi'})
        check(page.evaluate('window.__clicked.pop()') == '/watch?v=listCCC0003&list=PLhoshi', 'playlist item is opened by clicking its own link')
        run('play_item', {'id': 'nextBBB2222'})
        check(page.evaluate('window.__clicked.pop()') == '/watch?v=nextBBB2222&pp=x', 'up-next item is opened by clicking its link')
        check(page.evaluate('window.__hoshiYouTube.run("play_item", {id: "../../evil"})') is False, 'bad video ids are refused')
        page.goto('http://127.0.0.1:18799/')
        page.add_script_tag(content=SCRIPT)
        state = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        home = next((item for item in state.get('lists', []) if item['id'] == 'home'), {})
        check(state.get('page') == 'home' and state.get('badge') == 'рекомендации', 'YouTube home has a recommendations card without a player')
        check([i['id'] for i in home.get('items', [])] == ['homeAAA1111', 'homeBBB2222'], 'home feed lists loaded video cards')
        page.evaluate('window.dispatchEvent(new Event("scroll"))')
        state = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        home = next((item for item in state.get('lists', []) if item['id'] == 'home'), {})
        check([i['id'] for i in home.get('items', [])] == ['homeAAA1111', 'homeBBB2222', 'homeCCC3333'],
              'scrolling the open YouTube tab adds newly loaded recommendations')
        run('play_item', {'id': 'homeCCC3333'})
        check(page.evaluate('window.__clicked.pop()') == '/watch?v=homeCCC3333', 'phone can open a chosen home video in the current tab')
        page.evaluate('''() => {
          const feed = document.querySelector('#feed');
          for (let i = 0; i < 250; i++) {
            const card = document.createElement('ytd-rich-grid-media');
            card.innerHTML = `<a href="/watch?v=later${String(i).padStart(7, '0')}"></a><h3 id="video-title">Позднее предложение ${i} — длинное название видео</h3>`;
            feed.append(card);
          }
        }''')
        page.evaluate('window.scrollTo(0, document.body.scrollHeight)')
        page.wait_for_timeout(100)
        page.evaluate('window.dispatchEvent(new Event("scroll"))')
        state = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        home = next((item for item in state.get('lists', []) if item['id'] == 'home'), {})
        check(home.get('total') == 253 and home['items'][-1]['id'] == 'later0000249',
              'a long feed follows the current PC scroll position')
        check(len(json.dumps(state, ensure_ascii=False, separators=(',', ':')).encode('utf-8')) <= 32000,
              'recommendations stay within the phone packet budget')
        page.goto('http://127.0.0.1:18799/feed/subscriptions')
        page.add_script_tag(content=SCRIPT)
        page.wait_for_timeout(200)
        state = page.evaluate('window.__sent.filter(m => m.op === "state").pop().state')
        check('title' not in state and 'hint' in state, 'outside a video page nothing is read')
        browser.close()
    server.shutdown()
    print(f'HOSHI_YOUTUBE_EXTENSION_RESULT checks={checks} failures={failures}')
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()
