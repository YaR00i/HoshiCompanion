"""Offline package/VRM structure checks, Python 3.10+, standard library only.
Does NOT run Godot, validate shaders or certify full glTF/VRM conformance.
Run: python tests/validate_asset.py
"""
from __future__ import annotations
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'assets' / 'Hoshi_v1.vrm'
EXPECTED_SHA256 = 'fc919e08e37e7a9d2fac70d31c3582b3b4b3d62b500655b4e88e466a96ece21d'
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}

def verify() -> dict:
    data = MODEL.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    assert digest == EXPECTED_SHA256, 'Packaged Hoshi model differs from supplied source'
    magic, version, total = struct.unpack_from('<4sII', data)
    assert (magic, version, total) == (b'glTF', 2, len(data))
    chunks = []; offset = 12
    while offset < len(data):
        count, kind = struct.unpack_from('<I4s', data, offset); offset += 8
        assert count % 4 == 0 and offset + count <= len(data)
        chunks.append((kind, data[offset:offset + count])); offset += count
    assert [x[0] for x in chunks] == [b'JSON', b'BIN\0']
    source = json.loads(chunks[0][1]); binary = chunks[1][1]
    assert source['asset']['version'] == '2.0'
    vrm = source['extensions']['VRMC_vrm']
    assert vrm['specVersion'] == '1.0'
    assert len(source['buffers']) == 1
    assert source['buffers'][0]['byteLength'] <= len(binary)
    assert 'uri' not in source['buffers'][0]
    for view in source['bufferViews']:
        assert view['buffer'] == 0
        assert 0 <= view.get('byteOffset', 0)
        assert view.get('byteOffset', 0) + view['byteLength'] <= len(binary)
    for accessor in source['accessors']:
        # This specific VRoid export contains no sparse accessors / MAT3 padding.
        assert 'sparse' not in accessor
        view = source['bufferViews'][accessor['bufferView']]
        element_size = WIDTH[accessor['type']] * COMPONENT_SIZE[accessor['componentType']]
        stride = view.get('byteStride', element_size)
        assert stride >= element_size
        end = accessor.get('byteOffset', 0) + max(0, accessor['count'] - 1) * stride + element_size
        assert end <= view['byteLength']
    nodes = source['nodes']; parents = {}
    for i, node in enumerate(nodes):
        for child in node.get('children', []):
            assert 0 <= child < len(nodes) and child not in parents
            parents[child] = i
        for field, collection in [('mesh', source['meshes']), ('skin', source['skins'])]:
            if field in node:
                assert 0 <= node[field] < len(collection)
    for i in range(len(nodes)):
        seen = set()
        while i in parents:
            assert i not in seen, 'Cyclic node hierarchy'
            seen.add(i); i = parents[i]
    for item in vrm['humanoid']['humanBones'].values():
        assert 0 <= item['node'] < len(nodes)
    for skin in source['skins']:
        assert all(0 <= i < len(nodes) for i in skin['joints'])
        assert source['accessors'][skin['inverseBindMatrices']]['count'] == len(skin['joints'])
    triangles = 0
    for mesh in source['meshes']:
        for primitive in mesh['primitives']:
            assert primitive.get('mode', 4) == 4
            triangles += source['accessors'][primitive['indices']]['count'] // 3
            if 'targets' in primitive:
                assert len(primitive['targets']) == len(mesh['extras']['targetNames'])
    expressions = vrm['expressions']['preset']
    for required in ['blink', 'happy', 'sad', 'surprised', 'relaxed', 'aa']:
        assert required in expressions
    for definition in expressions.values():
        for bind in definition.get('morphTargetBinds', []):
            mesh = source['meshes'][nodes[bind['node']]['mesh']]
            assert 0 <= bind['index'] < len(mesh['extras']['targetNames'])
            assert 0 <= bind['weight'] <= 1
    for image in source['images']:
        assert 'uri' not in image
        assert 0 <= image['bufferView'] < len(source['bufferViews'])
    references = set()
    for suffix in ['*.gd', '*.tscn', 'project.godot']:
        for path in ROOT.rglob(suffix):
            for match in re.findall(r'"(res://[^"\n]+)"', path.read_text(encoding='utf-8')):
                references.add(match)
                assert (ROOT / match[6:]).exists(), f'Broken resource path: {match}'
    return {
        'status': 'passed',
        'scope': 'Python structural checks, not engine execution or full format certification',
        'model_sha256': digest, 'bytes': len(data), 'nodes': len(nodes),
        'meshes': len(source['meshes']), 'materials': len(source['materials']),
        'images': len(source['images']), 'accessors': len(source['accessors']),
        'triangles': triangles, 'humanoid_bones': len(vrm['humanoid']['humanBones']),
        'expressions': list(expressions), 'resource_paths_checked': len(references),
        'godot_executed': False, 'windows_tested': False,
    }

if __name__ == '__main__':
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
