"""Local-only Godot runner; no installs, network requests or global configuration."""
from __future__ import annotations
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ERRORS = re.compile(r'(?m)^(?:SCRIPT ERROR:|ERROR:)|Parse Error:|Failed to load script')

def run_step(engine: str, log_dir: Path, label: str, args: list[str], timeout: int = 180) -> dict:
    stdout_path = log_dir / (label + '.console.log')
    engine_log = log_dir / (label + '.engine.log')
    command = [engine, '--path', str(ROOT), '--log-file', str(engine_log), *args]
    started = dt.datetime.now().astimezone().isoformat()
    with stdout_path.open('w', encoding='utf-8') as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            code = -1
    text = stdout_path.read_text(encoding='utf-8', errors='replace')
    if engine_log.exists():
        text += '\n' + engine_log.read_text(encoding='utf-8', errors='replace')
    errors = [line for line in text.splitlines() if ERRORS.search(line)]
    result = {'step': label, 'started': started, 'exit_code': code, 'passed': code == 0 and not errors, 'errors': list(dict.fromkeys(errors)), 'log': str(stdout_path), 'command': command}
    if label == 'posture_capture':
        result['passed'] = result['passed'] and 'POSTURE_CAPTURE_DONE' in text
    if label in ['runtime', 'posture', 'shelf', 'shelf_windows', 'external_windows', 'edge_life', 'edge_views', 'cozy_windows', 'place', 'context', 'context_views']:
        marker = {'runtime': 'HOSHI_TEST_RESULT', 'posture': 'HOSHI_POSTURE_RESULT', 'shelf': 'HOSHI_SHELF_RESULT', 'shelf_windows': 'HOSHI_SHELF_RESULT', 'external_windows': 'HOSHI_EXTERNAL_RESULT', 'edge_life': 'HOSHI_EDGE_LIFE_RESULT', 'edge_views': 'HOSHI_EDGE_CAPTURE_RESULT', 'cozy_windows': 'HOSHI_COZY_RESULT', 'place': 'HOSHI_PLACE_RESULT', 'context': 'HOSHI_CONTEXT_RESULT', 'context_views': 'HOSHI_CONTEXT_CAPTURE_RESULT'}[label]
        markers = [line for line in text.splitlines() if marker in line]
        result['markers'] = list(dict.fromkeys(markers))
        result['passed'] = result['passed'] and bool(markers) and any(re.search(r'failures[\s\"\x27:=]+0', line) for line in markers)
    print(json.dumps(result, ensure_ascii=True), flush=True)
    return result

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['check', 'import', 'test', 'smoke', 'preview', 'desktop', 'editor', 'walk', 'capture', 'posture', 'poses', 'shelf', 'shelf_windows', 'shelf_demo', 'external_windows', 'edge_life', 'edge_views', 'cozy_windows', 'place', 'context', 'context_views'])
    opts = parser.parse_args()
    engine = (ROOT / 'godot_path.txt').read_text(encoding='utf-8-sig').strip()
    if not Path(engine).is_file():
        raise FileNotFoundError('Update godot_path.txt: ' + engine)
    stamp = dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    log_dir = ROOT / '.workspace' / 'checks' / stamp
    log_dir.mkdir(parents=True, exist_ok=False)
    version = subprocess.run([engine, '--version'], capture_output=True, text=True, timeout=15)
    summary = {'engine': version.stdout.strip(), 'mode': opts.mode, 'log_dir': str(log_dir), 'steps': []}
    stages = []
    if opts.mode in ['check', 'import', 'test', 'preview', 'desktop', 'editor', 'walk', 'capture', 'posture', 'poses', 'shelf', 'shelf_windows', 'shelf_demo', 'external_windows', 'edge_life', 'edge_views', 'cozy_windows', 'place', 'context', 'context_views']:
        stages.append(('import', ['--headless', '--import']))
    if opts.mode in ['check', 'test']:
        stages.append(('runtime', ['--headless', '--script', 'res://tests/test_runtime.gd']))
    if opts.mode in ['check', 'posture']:
        stages.append(('posture', ['--headless', '--script', 'res://tests/test_postures.gd', '--', '--test-mode']))
    if opts.mode in ['check', 'shelf']:
        stages.append(('shelf', ['--headless', '--script', 'res://tests/test_shelf.gd', '--', '--preview', '--test-mode']))
    if opts.mode in ['check', 'edge_life']:
        stages.append(('edge_life', ['--headless', '--script', 'res://tests/test_edge_life.gd', '--', '--test-mode']))
    if opts.mode == 'edge_views':
        stages.append(('edge_views', ['--script', 'res://tests/capture_edge_life.gd', '--', '--preview', '--test-mode', '--shelf-capture']))
    if opts.mode in ['check', 'place']:
        stages.append(('place', ['--headless', '--script', 'res://tests/test_place_director.gd', '--', '--test-mode']))
    if opts.mode in ['check', 'context']:
        stages.append(('context', ['--headless', '--script', 'res://tests/test_context_motion.gd', '--', '--test-mode']))
    if opts.mode == 'context_views':
        stages.append(('context_views', ['--script', 'res://tests/capture_context_motion.gd', '--', '--preview', '--test-mode']))
    if opts.mode == 'cozy_windows':
        stages.append(('cozy_windows', ['--script', 'res://tests/test_cozy.gd', '--', '--preview', '--test-mode', '--shelf-capture']))
    if opts.mode == 'external_windows':
        stages.append(('external_windows', ['--script', 'res://tests/test_external_windows.gd', '--', '--preview', '--test-mode']))
    if opts.mode == 'shelf_windows':
        stages.append(('shelf_windows', ['--script', 'res://tests/test_shelf.gd', '--', '--preview', '--test-mode', '--shelf-capture']))
    if opts.mode == 'poses':
        stages.append(('posture_capture', ['--script', 'res://tests/capture_postures.gd', '--', '--preview', '--test-mode']))
    if opts.mode in ['check', 'smoke']:
        stages.append(('smoke', ['--headless', '--quit-after', '120', '--fixed-fps', '30', '--', '--preview', '--test-mode']))
    if opts.mode == 'capture':
        stages.append(('capture', ['--quit-after', '240', '--', '--preview', '--capture', '--test-mode']))
    for label, args in stages:
        result = run_step(engine, log_dir, label, args)
        summary['steps'].append(result)
        if not result['passed']:
            break
    summary['passed'] = all(step['passed'] for step in summary['steps'])
    (log_dir / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    (ROOT / '.workspace' / 'last_check.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    if not summary['passed']:
        return 1
    if opts.mode in ['preview', 'desktop', 'editor', 'walk', 'shelf_demo']:
        args = ['--editor'] if opts.mode == 'editor' else ['--', '--desktop' if opts.mode == 'desktop' else '--preview']
        if opts.mode == 'walk':
            args.append('--walk-demo')
        if opts.mode == 'shelf_demo':
            args.append('--shelf-demo')
        process = subprocess.Popen([engine, '--path', str(ROOT), '--log-file', str(log_dir / 'session.log'), *args], cwd=ROOT)
        print('Started Godot PID=' + str(process.pid), flush=True)
    print('RESULT: PASS; logs=' + str(log_dir), flush=True)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
