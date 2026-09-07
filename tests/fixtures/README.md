# Fixtures

`mx-device-*.json` are `mx-device` responses. The `solaar-show-*.txt`
fixtures that used to sit beside them went with the text parser in phase C:
the plugin no longer invokes `solaar`, so a fixture of its output tests
nothing. They remain in git history at the `v1.0.0` tag if the old parser
ever needs re-reading.

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
