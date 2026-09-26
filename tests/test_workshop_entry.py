"""The workshop launcher must enter its editable scene, not the main app scene."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import dev


def main() -> None:
    launcher = (ROOT / 'ANIMATION_WORKSHOP_WINDOWS.bat').read_text(encoding='utf-8')
    assert 'python tools\\dev.py workshop_editor' in launcher
    assert dev.interactive_args('workshop_editor') == [
        '--editor', 'res://scenes/animation_authoring_3d.tscn'
    ]
    print('HOSHI_WORKSHOP_ENTRY_RESULT checks=2 failures=0')


if __name__ == '__main__':
    main()
