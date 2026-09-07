"""Records what mx-device asks of the transport layer.

The point of recording `find_paired_node`'s timeout is feature 004's one
non-obvious performance requirement: Solaar's own default is a one-second
busy-wait per device that cannot succeed for receiver-paired devices, and a
future refactor that quietly restores it costs two seconds per invocation
with no visible symptom. So the budget is asserted, not trusted.
"""
import json, os

LOG = os.environ.get("MXD_STUB_LOG")


def _record(event, **fields):
    if not LOG:
        return
    with open(LOG, "a") as fh:
        fh.write(json.dumps(dict(event=event, **fields)) + "\n")


def receivers():
    if os.environ.get("MXD_STUB_NO_RECEIVER") == "1":
        return []
    return [{"path": "/dev/stub0"}]


def find_paired_node(receiver_path, index, timeout):
    _record("find_paired_node", index=index, timeout=timeout)
    return None
