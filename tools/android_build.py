"""Build the Android app «Хоши» and hand it to Hoshi for auto-update.

    python tools/dev.py android      (or: python tools/android_build.py)

Needs Android Studio installed once (it brings Java and the Android SDK) and
the project android/ opened in it once (it downloads Gradle). Then this:
  1. finds Java (Android Studio's own "jbr") and the Android SDK;
  2. builds the debug APK with Gradle (android/gradlew.bat, or the Gradle
     that Android Studio downloaded);
  3. copies it to .workspace/android/hoshi.apk and writes version.json with
     versionCode/versionName from android/app/build.gradle.kts.
Hoshi serves both at http://<PC>:18770/app/… — the app on the phone sees a
higher versionCode and offers «Обновить». Remember to raise versionCode in
android/app/build.gradle.kts for every build that should reach the phone.
Nothing is downloaded by this script itself (Gradle may fetch libraries).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / 'android'
OUT = ROOT / '.workspace' / 'android'
GRADLE_VERSION = '8.11.1'


def find_java() -> Path | None:
    # Gradle 8.11 runs on Java 8..23. Android Studio's own "jbr" may be newer (25), so prefer
    # a Java 17/21 that Android Studio downloaded into ~/.jdks («Use JVM 21»), then the rest.
    jdks = sorted((Path.home() / '.jdks').glob('*'), reverse=True) if (Path.home() / '.jdks').is_dir() else []
    preferred = [str(j) for j in jdks if re.search(r'(^|\D)(21|17)(\D|$)', j.name)]
    candidates = preferred + [os.environ.get('JAVA_HOME', ''),
                  r'C:\Program Files\Android\Android Studio\jbr',
                  str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs' / 'Android Studio' / 'jbr')]
    for folder in candidates:
        if folder and (Path(folder) / 'bin' / 'java.exe').is_file():
            return Path(folder)
    return None


def find_sdk() -> Path | None:
    candidates = [os.environ.get('ANDROID_HOME', ''), os.environ.get('ANDROID_SDK_ROOT', ''),
                  str(Path(os.environ.get('LOCALAPPDATA', '')) / 'Android' / 'Sdk')]
    for folder in candidates:
        if folder and (Path(folder) / 'platform-tools').is_dir():
            return Path(folder)
    return None


def find_gradle() -> list[str] | None:
    wrapper = ANDROID / 'gradlew.bat'
    if wrapper.is_file() and (ANDROID / 'gradle' / 'wrapper' / 'gradle-wrapper.jar').is_file():
        return [str(wrapper)]
    dists = Path.home() / '.gradle' / 'wrapper' / 'dists' / ('gradle-%s-bin' % GRADLE_VERSION)
    for gradle in sorted(dists.glob('*/gradle-%s/bin/gradle.bat' % GRADLE_VERSION)):
        return [str(gradle)]
    return None


def version_of() -> dict:
    text = (ANDROID / 'app' / 'build.gradle.kts').read_text(encoding='utf-8')
    code = re.search(r'versionCode\s*=\s*(\d+)', text)
    name = re.search(r'versionName\s*=\s*"([^"]+)"', text)
    return {'versionCode': int(code.group(1)) if code else 1, 'versionName': name.group(1) if name else '0'}


def main() -> int:
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    java, sdk, gradle = find_java(), find_sdk(), find_gradle()
    problems = []
    if java is None:
        problems.append('нет Java — установи Android Studio (в нём есть «jbr»)')
    if sdk is None:
        problems.append('нет Android SDK — запусти Android Studio и пройди мастер «Standard»')
    if gradle is None:
        problems.append('нет Gradle — открой папку android/ в Android Studio один раз (он скачает Gradle %s)' % GRADLE_VERSION)
    if problems:
        print('ANDROID_BUILD not ready: ' + '; '.join(problems), flush=True)
        return 1
    (ANDROID / 'local.properties').write_text('sdk.dir=' + str(sdk).replace('\\', '\\\\') + '\n', encoding='utf-8')
    env = dict(os.environ, JAVA_HOME=str(java), ANDROID_HOME=str(sdk))
    result = subprocess.run(gradle + ['--no-daemon', 'assembleDebug'], cwd=ANDROID, env=env)
    apk = ANDROID / 'app' / 'build' / 'outputs' / 'apk' / 'debug' / 'app-debug.apk'
    if result.returncode != 0 or not apk.is_file():
        print('ANDROID_BUILD failed (Gradle exit %d)' % result.returncode, flush=True)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(apk, OUT / 'hoshi.apk')
    version = version_of()
    (OUT / 'version.json').write_text(json.dumps(version), encoding='utf-8')
    print('ANDROID_BUILD ok versionCode=%d apk=%s (%d KB)' % (version['versionCode'], OUT / 'hoshi.apk', (OUT / 'hoshi.apk').stat().st_size // 1024), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
