# Fixtures

`solaar-show-*.txt` are captured `solaar show` output, from 1.0.0's data path.
`mx-device-*.json` are `mx-device` responses, from 1.1's.

Only one of the JSON fixtures is *captured* from the reference hardware:
`mx-device-keyboard-and-mouse.json`. The rest are **constructed** against the
contract in `specs/004-single-transport/spec.md`, because the states they
describe cannot be produced on demand here — a missing receiver means
unplugging one, and a degraded frame is by definition intermittent. They are
written from observed failures rather than imagined ones (see the spec's
"Consequence 1"), but the distinction matters and is recorded rather than
implied.

Note that `mx-device` output carries no device serials, unlike `solaar show`
— which is why this directory once had to have a real one redacted out of it.
