"""Offline hotfix contract checks. Does not compile or execute GDScript.
Run alongside validate_asset.py. Python 3.10+, standard library only.
"""
from __future__ import annotations
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify() -> dict:
    checks: list[str] = []

    def check(ok: bool, name: str) -> None:
        if not ok:
            raise AssertionError(name)
        checks.append(name)

    expr = (ROOT / 'scripts/expression_driver.gd').read_text(encoding='utf-8')
    stage = (ROOT / 'scripts/avatar_stage.gd').read_text(encoding='utf-8')
    source_code = (ROOT / 'scripts/vrm_source.gd').read_text(encoding='utf-8')
    main = (ROOT / 'scripts/companion.gd').read_text(encoding='utf-8')
    active = '\n'.join(line for line in expr.splitlines() if not line.lstrip().startswith('#'))
    check('state.get_scene_node(' not in active, 'no runtime mesh lookup through temporary GLTF scene-node pointers')
    check('find_children("*", "MeshInstance3D", true, false)' in active,
          'binding enumerates the live generated scene')
    check('Source.NODE_MARKER' in active and 'Source.MESH_MARKER' in active,
          'runtime resolver consumes source-identity markers')
    check('"Ambiguous runtime meshes' in active,
          'ambiguous instance matching is explicitly rejected')
    check('if not bindings.has("blink"):\n\t\treturn {"error"' not in active,
          'missing blink is not returned as a fatal load error')
    check('if face_report.has("error")' not in stage,
          'stage does not abort all animation for missing optional face capabilities')
    check(stage.index('rig.tick(0.0') < stage.index('expressions.setup(avatar,'),
          'idle body pose initialized before expression binding')
    check('"status": "ready" if bool(face_report.get("blink_available", false)) else "partial"' in stage,
          'partial capability has a distinct status')
    check('native: Dictionary = document.duplicate(true)' in source_code,
          'runtime tagging works on a deep JSON copy')
    check('extras[NODE_MARKER] = index' in source_code and 'extras[MESH_MARKER] = index' in source_code,
          'source-node and source-mesh indices are tagged independently')
    check('_write_diagnostics(avatar_path, result)' in main and 'HOSHI_LOAD_DIAGNOSTICS' in main,
          'both successful and failed startup results reach local diagnostics')

    data = (ROOT / 'assets/Hoshi_v1.vrm').read_bytes()
    json_size = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20 + json_size])
    binds = document['extensions']['VRMC_vrm']['expressions']['preset']
    check(bool(binds['blink'].get('morphTargetBinds')), 'supplied avatar has an explicit blink morph bind')
    blink_bind = binds['blink']['morphTargetBinds'][0]
    face_mesh_id = document['nodes'][blink_bind['node']]['mesh']
    names = document['meshes'][face_mesh_id]['extras']['targetNames']
    check(bool(names), 'supplied Face source contains named morph targets')
    check(0 <= blink_bind['index'] < len(names) and blink_bind['weight'] > 0,
          'blink bind references an active face morph target')
    check(bool(names[blink_bind['index']]), 'blink target has a source name')
    check(len([n for n in document['nodes'] if n.get('mesh') == face_mesh_id]) == 1,
          'supplied avatar has a unique live instance candidate for its face mesh')
    check(not any('_hoshi_source_mesh_v1' in m.get('extras', {}) for m in document['meshes']),
          'supplied model on disk has not been tagged or rewritten')
    check(len(names) == len(set(names)), 'all face morph names are unique')
    for name, definition in binds.items():
        for bind in definition.get('morphTargetBinds', []):
            mesh_id = document['nodes'][bind['node']]['mesh']
            target_names = document['meshes'][mesh_id]['extras']['targetNames']
            check(0 <= bind['index'] < len(target_names) and bool(target_names[bind['index']]),
                  f'source preset {name} has a valid named target')
    runtime = (ROOT / 'tests/test_runtime.gd').read_text(encoding='utf-8')
    check('actual Hoshi must be fully ready' in runtime and '_check_degraded_startup' in runtime,
          'engine regression tests separately require real blink and graceful degradation')
    check('arms are lowered from T-pose' in runtime and 'actual morph channel' in runtime,
          'engine regression tests check concrete bones and actual morph values')
    project_text = (ROOT / 'project.godot').read_text(encoding='utf-8')
    version_match = re.search(r'(?m)^config/version="([^"]+)"', project_text)
    check(version_match is not None and
          f'3D / {version_match.group(1)}' in (ROOT / 'scripts/companion_ui.gd').read_text(encoding='utf-8'),
          'project version is visible in UI')
    for file in ROOT.rglob('*.gd'):
        code = file.read_text(encoding='utf-8')
        check('\x00' not in code, f'no null bytes in {file.relative_to(ROOT)}')
        indented_lines = [line for line in code.splitlines() if line.strip() and not line.lstrip().startswith('#')]
        # A formatting check, not a language grammar or type check.
        check(all(' ' not in re.match(r'^[\t ]*', line).group(0) for line in indented_lines),
              f'consistent tab indentation {file.relative_to(ROOT)}')
    return {'status': 'passed', 'scope': 'Python asset/contract checks only; not GDScript execution or grammar validation',
            'checks': checks, 'check_count': len(checks), 'godot_executed': False, 'windows_tested': False}


if __name__ == '__main__':
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
