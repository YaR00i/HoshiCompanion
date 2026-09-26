"""Visual scan regression for dense browser chrome and sparse file rows."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.workspace' / 'surface-deps'))
sys.path.insert(0, str(ROOT / 'tools'))

import cv2
import numpy as np
from window_visual_surfaces import lines_from_frame


def main() -> None:
    frame = np.full((800, 1100, 3), 35, dtype=np.uint8)
    for y in range(24, 204, 6):
        cv2.line(frame, (80, y), (700, y), (180, 180, 180), 1)
    for index in range(17):
        y = 260 + 22 * index
        cv2.rectangle(frame, (170, y), (255, y + 11), (210, 210, 210), -1)
        cv2.rectangle(frame, (430, y + 1), (510, y + 10), (170, 170, 170), -1)
    cv2.line(frame, (20, 742), (1040, 742), (245, 245, 245), 2)

    result = lines_from_frame(frame)
    assert any(item['kind'] == 'Visual' and item['y'] >= 730
               for item in result['candidates']), result
    rows = [item for item in result['candidates'] if item['kind'] == 'VisualItem'
            and 250 <= item['y'] <= 650 and 150 <= item['x'] <= 280]
    assert len(rows) >= 3, result
    print('HOSHI_WINDOW_VISUAL_RESULT checks=2 failures=0')


if __name__ == '__main__':
    main()
