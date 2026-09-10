#!/bin/bash
#
# The generated rules fire for real frames, judged by Solaar's OWN engine.
#
# The unit tests prove the YAML matches its generator. They cannot prove the
# byte offsets mean what we think: a rule testing the wrong byte still parses,
# still loads, and silently never fires. So this loads solaar-rule.yaml
# through logitech_receiver.diversion, builds notifications from frames
# captured off /dev/hidraw2 during real key presses, and asks which rule
# would run. It is the test that separates "the rule is wrong" from "Solaar
# is not evaluating" -- the hour lost on 2026-09-10 (AGENTS.md).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
python3 -c "import logitech_receiver.diversion" 2>/dev/null \
  || skip "Solaar's logitech_receiver is not importable; the engine check needs it"

python3 - "$ROOT/solaar-rule.yaml" <<'PY' 2> >(grep -v "rules cannot access modifier keys" >&2)
import sys
import logitech_receiver.diversion as D
from logitech_receiver.hidpp20_constants import SupportedFeature
from logitech_receiver.base import make_notification

D._file_path = sys.argv[1]
D.load_config_rule_file()

def leaves(rule, out):
    kids = [c for c in rule.components if isinstance(c, D.Rule)]
    if kids:
        for k in kids: leaves(k, out)
    else:
        out.append(rule)
    return out

# The file's rules sit under the first top-level component; Solaar's own
# built-ins under the second. Only ours carry an Execute we recognise.
ours = [r for r in leaves(D.rules, [])
        if any(isinstance(c, D.Action) and "mx-quick-control" in str(c) for c in r.components)]

failed = False
def ok(desc):
    print(f"ok - {desc}")
def not_ok(desc, detail=""):
    global failed
    failed = True
    if detail: print(detail, file=sys.stderr)
    print(f"not ok - {desc}", file=sys.stderr)

if len(ours) == 129:
    ok("Solaar loads all 129 rules (128 pairs + catch-all)")
else:
    not_ok("Solaar loads all 129 rules (128 pairs + catch-all)", f"loaded {len(ours)}")

def fired_for(hexframe):
    raw = bytes.fromhex(hexframe)
    n = make_notification(raw[0], raw[1], raw[2:])
    for r in ours:
        conds = [c for c in r.components if isinstance(c, D.Condition)]
        acts = [c for c in r.components if isinstance(c, D.Action)]
        if conds and acts and all(c.evaluate(SupportedFeature.BACKLIGHT2, n, None, None) for c in conds):
            return str(acts[0]).split("ipc call ")[1].split("alebairos.mx-quick-control ")[1]
    return None

# Frames captured on the reference keyboard: report 0x11, device 1, feature
# index 0x0b (BACKLIGHT2), address 0x00, then [levels, level, ?, effect].
cases = [
    ("11010b0008040500", "externalState 4:0",  "F4/F5 at level 4 on Static passes 4:0"),
    ("11010b0008070503", "externalState 7:3",  "effect key to Contrast at level 7 passes 7:3"),
    ("11010b0008000501", "externalState 0:1",  "level 0 with the Off effect still passes 0:1"),
    ("11010b000807050f", "externalState 7:15", "the highest effect index passes 7:15"),
    ("11010b0008090500", "deviceChanged",      "a level beyond 8 falls through to the catch-all"),
]
for hexframe, expected, desc in cases:
    got = fired_for(hexframe)
    if got == expected:
        ok(desc)
    else:
        not_ok(desc, f"frame {hexframe}: expected `{expected}`, got `{got}`")

sys.exit(1 if failed else 0)
PY
