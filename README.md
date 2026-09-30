# LiteLLM Usage for VS Code

[![CI](https://github.com/mesutpiskin/litellm-usage/actions/workflows/ci.yml/badge.svg)](https://github.com/mesutpiskin/litellm-usage/actions/workflows/ci.yml)
[![Visual Studio Marketplace](https://img.shields.io/visual-studio-marketplace/v/mesutpiskin.litellm-usage?label=marketplace)](https://marketplace.visualstudio.com/items?itemName=mesutpiskin.litellm-usage)
[![Open VSX](https://img.shields.io/open-vsx/v/mesutpiskin/litellm-usage?label=open%20vsx)](https://open-vsx.org/extension/mesutpiskin/litellm-usage)

Keep an eye on your [LiteLLM](https://github.com/BerriAI/litellm) proxy spend, token and model usage without leaving your editor.

**No admin account required** — sign in with your own virtual key (`sk-…`) or your LiteLLM UI username and password.

## Features

- **Status bar** — today's spend (or today's tokens / total spend) at a glance, with a quick summary on hover.
- **Usage dashboard**
  - Total spend vs. budget, budget reset date, RPM / TPM limits
  - Spend, total tokens, input / output tokens, requests and failures for today, 7, 30 or 90 days
  - Daily chart (spend, tokens or requests)
  - Per-model breakdown
  - All keys that belong to you and their spend
  - Models available to your key
- **Scope switch** — usage across all your keys, or just the key you signed in with.
- **Secure** — credentials are kept in VS Code SecretStorage (macOS Keychain, Windows Credential Manager, libsecret on Linux).
- **Enterprise friendly** — honours VS Code proxy settings and can trust self-signed certificates.

## Getting started

1. Install **LiteLLM Usage** from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=mesutpiskin.litellm-usage) or [Open VSX](https://open-vsx.org/extension/mesutpiskin/litellm-usage) (Cursor, VSCodium, Windsurf…).
2. Click **LiteLLM: Sign in** in the status bar, or run `LiteLLM: Sign In` from the Command Palette.
3. Enter your proxy URL (e.g. `https://litellm.example.com`) and choose a sign-in method:
   - **API Key** — a virtual key created in the LiteLLM UI under *Virtual Keys*.
   - **Username / Password** — your LiteLLM UI credentials. If you choose to store the password, the session is renewed automatically when it expires. SSO logins are not supported; use an API key instead.
4. Click the status bar item to open the dashboard.

## Commands

| Command | Description |
|---|---|
| `LiteLLM: Show Usage Dashboard` | Open the dashboard |
| `LiteLLM: Sign In` | Sign in or switch account |
| `LiteLLM: Sign Out` | Remove stored credentials |
| `LiteLLM: Refresh` | Refresh now |

## Settings

| Setting | Default | Description |
|---|---|---|
| `litellm.baseUrl` | `""` | Base URL of your LiteLLM proxy |
| `litellm.refreshMinutes` | `5` | Auto-refresh interval in minutes |
| `litellm.statusBar` | `todaySpend` | `todaySpend`, `todayTokens`, `totalSpend` or `icon` |
| `litellm.allowInsecureTLS` | `false` | Accept self-signed / untrusted certificates |

## LiteLLM endpoints used

| Endpoint | Purpose |
|---|---|
| `GET /key/info` | Key spend, budget and limits |
| `GET /user/info` | User spend and list of keys |
| `GET /user/daily/activity` | Daily and per-model tokens and spend |
| `GET /v1/models` | Models available to the key |
| `POST /login`, `POST /v2/login` | Username / password sign-in |

Daily and per-model breakdowns need a LiteLLM version that exposes `/user/daily/activity`. On older versions only total spend is shown.

## Development

```bash
npm install
npm test          # compile + unit tests against a mock LiteLLM server
npm run package   # build a .vsix
```

Press <kbd>F5</kbd> in VS Code to launch an Extension Development Host.

## Releasing

1. Bump `version` in `package.json` and add an entry to `CHANGELOG.md`.
2. Tag and push:
   ```bash
   git tag v0.3.0 && git push origin v0.3.0
   ```

The **Release** workflow runs the tests, packages the `.vsix`, attaches it to a GitHub Release and publishes it to the Visual Studio Marketplace and Open VSX.

### Marketplace credentials

Pick one (the workflow uses the first one it finds):

| Method | Configuration |
|---|---|
| **Microsoft Entra ID (recommended)** | Repository variables `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` of an app registration with a GitHub federated credential, added as a member of the `mesutpiskin` publisher. See [Publishing extensions](https://code.visualstudio.com/api/working-with-extensions/publishing-extension). |
| Global PAT (legacy) | Secret `VSCE_PAT` — an Azure DevOps PAT for *All accessible organizations* with the **Marketplace › Manage** scope. Azure DevOps retires global PATs on **2026-12-01**. |
| Manual | No credentials: download the `.vsix` from the GitHub Release and upload it at [marketplace.visualstudio.com/manage](https://marketplace.visualstudio.com/manage). |

Open VSX uses the `OVSX_PAT` secret from [open-vsx.org](https://open-vsx.org/user-settings/tokens) and is skipped when it is missing.

## License

[MIT](LICENSE)
