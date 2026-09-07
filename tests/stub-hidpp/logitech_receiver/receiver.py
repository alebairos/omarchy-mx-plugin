import json, os
from . import base as _base
from .hidpp20_constants import SupportedFeature


class _Battery:
    def __init__(self, level):
        self.level = level


class _Device:
    def __init__(self, number, name, backlit):
        self.number = number
        self._name = name
        self._backlit = backlit
        self._reads = 0

    @property
    def name(self):
        return self._name

    def ping(self):
        _base._record("ping", index=self.number)
        return True

    @property
    def features(self):
        return [SupportedFeature.BACKLIGHT2] if self._backlit else []

    def battery(self):
        return _Battery(65 if self._backlit else 35)

    def feature_request(self, feature, fn, *args):
        if not self._backlit:
            return None
        if fn == 0x10:  # SET_CONFIG
            _base._record("write", index=self.number)
            return b"\x00" if os.environ.get("MXD_STUB_REJECT") != "1" else None
        self._reads += 1
        degraded = int(os.environ.get("MXD_STUB_DEGRADED_READS", "0"))
        # Each *pair* of requests (config, state) is one attempt; degrade the
        # first N attempts, then answer properly.
        attempt = (self._reads + 1) // 2
        if fn == 0x00:  # GET_CONFIG
            if attempt <= degraded:
                # A well-formed frame with an empty effects bitmap: exactly
                # what contention produces, and never an error.
                return bytes(16)
            return bytes([0x01, 0x1D, 0x3D, 0x7F, 0x00, 0x06, 0x06, 0x00,
                          0x06, 0x00, 0x3C, 0x00, 0, 0, 0, 0])
        if fn == 0x20:  # GET_STATE
            if attempt <= degraded:
                return bytes(16)
            return bytes([0x08, 0x06, 0x05, 0x02, 0x03, 0, 0, 0,
                          0, 0, 0, 0, 0, 0, 0, 0])
        return None


def create_receiver(low_level, info, setting_callback=None):
    # `low_level` is the caller's own module, which is how mx-device injects
    # its node-probe budget. The real Device constructor reaches the probe
    # through exactly this handle, so the stub must too -- calling `base`
    # directly here would silently test the unshimmed path.
    if os.environ.get("MXD_STUB_NO_DEVICES") == "1":
        return _Receiver(low_level, [])
    return _Receiver(low_level, [_Device(1, "Stub Keyboard", True),
                                 _Device(2, "Stub Mouse", False)])


class _Receiver:
    def __init__(self, low_level, devices):
        self._low_level = low_level
        self._devices = devices
        self.path = "/dev/stub0"

    def __iter__(self):
        # Constructing a Device is what pays the node probe in the real
        # library, so the stub does it here too -- and through low_level,
        # passing the same 1s default the real constructor hardcodes.
        for d in self._devices:
            self._low_level.find_paired_node(self.path, d.number, 1)
            yield d
