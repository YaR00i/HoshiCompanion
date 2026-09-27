"""Sound output devices: list them, tell which one is the default, switch it.

"Звук: переключение устройств" (docs/REMOTE_APP_PLAN_RU.md).
Allowed by the user on 2026-09-27: device FRIENDLY NAMES and which one is the
default only. Never reads which programs play, what plays, volume or anything
else. Uses Windows Core Audio through ctypes; nothing to download or build.

Switching changes only the ordinary default (console + multimedia roles); the
"communications" default (Discord, calls) is left alone by the user's choice.
Windows has no public call for this; like SoundSwitch/EarTrumpet we use the
undocumented IPolicyConfig, stable on Windows 10/11.

    python tools/audio_devices.py list          # JSON to stdout
    python tools/audio_devices.py set <id>      # only an active output id from `list`
"""
from __future__ import annotations

import ctypes as C
from ctypes import wintypes as W
import json
import sys
import uuid

CLSID_MMDEVICE_ENUMERATOR = '{BCDE0395-E52F-467C-8E3D-C4579291692E}'
IID_IMMDEVICE_ENUMERATOR = '{A95664D2-9614-4F35-A746-DE8DB63617E6}'
CLSID_POLICY_CONFIG_CLIENT = '{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}'
IID_POLICY_CONFIG = '{F8679F50-850A-41CF-9C72-430F290290C8}'
POLICY_SET_DEFAULT_ENDPOINT = 13  # IPolicyConfig vtable slot
PKEY_FRIENDLY_NAME = ('{A45C254E-DF1C-4EFD-8020-67D146A850E0}', 14)
CLSCTX_ALL = 0x17
COINIT_APARTMENTTHREADED = 0x2
STGM_READ = 0
E_NOTFOUND = 0x80070490
VT_LPWSTR = 31

RENDER = 0                      # EDataFlow eRender: output devices only
ROLE_CONSOLE, ROLE_MULTIMEDIA, ROLE_COMMUNICATIONS = 0, 1, 2
STATE_ALL = 0xF
STATES = {1: 'active', 2: 'disabled', 4: 'not_present', 8: 'unplugged'}


class GUID(C.Structure):
    _fields_ = [('data1', W.DWORD), ('data2', W.WORD), ('data3', W.WORD), ('data4', C.c_ubyte * 8)]

    @classmethod
    def parse(cls, text: str) -> 'GUID':
        return cls.from_buffer_copy(uuid.UUID(text).bytes_le)


class PROPERTYKEY(C.Structure):
    _fields_ = [('fmtid', GUID), ('pid', W.DWORD)]


class PROPVARIANT(C.Structure):
    # vt + 3 reserved words, then a 16-byte union; only the string pointer is used.
    _fields_ = [('vt', W.USHORT), ('r1', W.WORD), ('r2', W.WORD), ('r3', W.WORD),
                ('pwszVal', C.c_void_p), ('pad', C.c_void_p)]


class ComError(Exception):
    def __init__(self, where: str, hr: int):
        super().__init__(f'{where}: 0x{hr & 0xFFFFFFFF:08X}')
        self.hr = hr & 0xFFFFFFFF


def _call(obj: C.c_void_p, index: int, where: str, *args: tuple) -> None:
    """Call method number `index` of a COM object; args are (ctype, value) pairs."""
    vtable = C.cast(obj, C.POINTER(C.POINTER(C.c_void_p)))[0]
    proto = C.WINFUNCTYPE(C.c_long, C.c_void_p, *[a[0] for a in args])
    hr = proto(vtable[index])(obj, *[a[1] for a in args])
    if hr < 0:
        raise ComError(where, hr)


def _release(obj: C.c_void_p) -> None:
    if obj:
        vtable = C.cast(obj, C.POINTER(C.POINTER(C.c_void_p)))[0]
        C.WINFUNCTYPE(C.c_ulong, C.c_void_p)(vtable[2])(obj)


def _device_id(ole32, device: C.c_void_p) -> str:
    text = C.c_void_p()
    _call(device, 5, 'GetId', (C.POINTER(C.c_void_p), C.byref(text)))
    try:
        return C.wstring_at(text.value)
    finally:
        ole32.CoTaskMemFree(text)


def _friendly_name(ole32, device: C.c_void_p) -> str:
    store = C.c_void_p()
    _call(device, 4, 'OpenPropertyStore', (W.DWORD, STGM_READ), (C.POINTER(C.c_void_p), C.byref(store)))
    try:
        key = PROPERTYKEY(GUID.parse(PKEY_FRIENDLY_NAME[0]), PKEY_FRIENDLY_NAME[1])
        value = PROPVARIANT()
        try:
            _call(store, 5, 'GetValue', (C.POINTER(PROPERTYKEY), C.byref(key)),
                  (C.POINTER(PROPVARIANT), C.byref(value)))
        except ComError:
            return ''  # long-gone devices may have no readable properties left

        try:
            return C.wstring_at(value.pwszVal) if value.vt == VT_LPWSTR and value.pwszVal else ''
        finally:
            ole32.PropVariantClear(C.byref(value))
    finally:
        _release(store)


def _default_id(ole32, enumerator: C.c_void_p, role: int) -> str:
    device = C.c_void_p()
    try:
        _call(enumerator, 4, 'GetDefaultAudioEndpoint', (C.c_int, RENDER), (C.c_int, role),
              (C.POINTER(C.c_void_p), C.byref(device)))
    except ComError as error:
        if error.hr == E_NOTFOUND:
            return ''
        raise
    try:
        return _device_id(ole32, device)
    finally:
        _release(device)


def _ole32():
    ole32 = C.WinDLL('ole32')
    ole32.CoTaskMemFree.argtypes = [C.c_void_p]
    ole32.PropVariantClear.argtypes = [C.c_void_p]
    ole32.CoCreateInstance.argtypes = [C.POINTER(GUID), C.c_void_p, W.DWORD, C.POINTER(GUID),
                                       C.POINTER(C.c_void_p)]
    ole32.CoCreateInstance.restype = C.c_long
    ole32.CoInitializeEx(None, COINIT_APARTMENTTHREADED)
    return ole32


def _create(ole32, clsid: str, iid: str, out: C.c_void_p) -> None:
    hr = ole32.CoCreateInstance(C.byref(GUID.parse(clsid)), None, CLSCTX_ALL,
                                C.byref(GUID.parse(iid)), C.byref(out))
    if hr < 0:
        raise ComError('CoCreateInstance', hr)


def set_default(device_id: str) -> dict:
    """Make an ACTIVE output device the ordinary default; communications stay as they are."""
    before = list_devices()
    if not before['ok']:
        return before
    if not any(d['id'] == device_id and d['state'] == 'active' for d in before['devices']):
        return {'ok': False, 'error': 'not_active', 'devices': before['devices']}
    ole32 = _ole32()
    policy = C.c_void_p()
    try:
        _create(ole32, CLSID_POLICY_CONFIG_CLIENT, IID_POLICY_CONFIG, policy)
        for role in (ROLE_CONSOLE, ROLE_MULTIMEDIA):
            _call(policy, POLICY_SET_DEFAULT_ENDPOINT, 'SetDefaultEndpoint',
                  (W.LPCWSTR, device_id), (C.c_int, role))
    except ComError as error:
        return {'ok': False, 'error': str(error), 'devices': before['devices']}
    finally:
        _release(policy)
        ole32.CoUninitialize()
    after = list_devices()
    if after['ok'] and not any(d['id'] == device_id and d['default'] for d in after['devices']):
        after = {'ok': False, 'error': 'not_switched', 'devices': after['devices']}
    return after


def list_devices() -> dict:
    if not hasattr(C, 'WinDLL'):
        return {'ok': False, 'error': 'windows_only', 'devices': []}
    ole32 = _ole32()
    enumerator = C.c_void_p()
    collection = C.c_void_p()
    try:
        _create(ole32, CLSID_MMDEVICE_ENUMERATOR, IID_IMMDEVICE_ENUMERATOR, enumerator)
        default_media = _default_id(ole32, enumerator, ROLE_MULTIMEDIA)
        default_comms = _default_id(ole32, enumerator, ROLE_COMMUNICATIONS)
        _call(enumerator, 3, 'EnumAudioEndpoints', (C.c_int, RENDER), (W.DWORD, STATE_ALL),
              (C.POINTER(C.c_void_p), C.byref(collection)))
        count = W.UINT()
        _call(collection, 3, 'GetCount', (C.POINTER(W.UINT), C.byref(count)))
        devices = []
        for index in range(count.value):
            device = C.c_void_p()
            _call(collection, 4, 'Item', (W.UINT, index), (C.POINTER(C.c_void_p), C.byref(device)))
            try:
                device_id = _device_id(ole32, device)
                state = W.DWORD()
                _call(device, 6, 'GetState', (C.POINTER(W.DWORD), C.byref(state)))
                devices.append({
                    'id': device_id,
                    'name': _friendly_name(ole32, device),
                    'state': STATES.get(state.value, 'unknown'),
                    'default': device_id == default_media,
                    'default_comms': device_id == default_comms,
                })
            finally:
                _release(device)
        return {'ok': True, 'devices': devices}
    except ComError as error:
        return {'ok': False, 'error': str(error), 'devices': []}
    finally:
        _release(collection)
        _release(enumerator)
        ole32.CoUninitialize()


def main(argv: list[str]) -> int:
    if argv[1:] == ['list']:
        result = list_devices()
    elif len(argv) == 3 and argv[1] == 'set':
        result = set_default(argv[2])
    else:
        print('usage: audio_devices.py list | set <device id>', file=sys.stderr)
        return 2
    sys.stdout.reconfigure(encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
