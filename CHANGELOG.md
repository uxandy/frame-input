# Changelog

## 0.1.3-alpha — 2026-10-26

- First public source release with complete setup, daily-use, troubleshooting, update/removal guides, and MIT license.
- Recorded the tester's confirmation that Windows and Frame shortcuts work; clarified remaining fault and streaming-focus tests.
- Added Linux and Windows CI, contribution guidance, and source-only packaging with an integrity manifest.
- Documented the unplugged-receiver discovery symptom and existing sudo rule-order fix.
- Runtime scripts are unchanged from 0.1.2-alpha. Existing working users do not need to reinstall.

## 0.1.2-alpha — 2026-10-25

- Install the narrow sudo fragment as `zz-frame-input` so it follows the observed SteamOS wheel rule.
- Check passwordless Stop as the selected user without cached credentials before completing a fresh install; roll back on failure.
- Uninstall accepts one unchanged rule at either the old or new filename and rejects ambiguity or modifications.

## 0.1.1-alpha — 2026-10-25

- Default to manual stopping with `--minutes 0`; retain optional deadlines of 1–480 minutes.
- Update the start dialog to explain manual stopping.

## 0.1.0-alpha — 2026-10-25

- Initial on-demand Frame service and desktop/Steam-compatible launchers.
- Windows receiver setup and targeted Use/Return shortcuts through the official VirtualHere client API.
