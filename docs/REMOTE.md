# VoltaDock remote protocol (desktop ⇄ iPad)

The iPad app is a companion: it never runs Claude Code. It connects to the
desktop app (Windows today, macOS later) over the local network to see the
Claude Code sessions and to answer permission requests.

Design rules, inherited from the desktop app:

- **Off by default.** The desktop app only listens once the user turns on
  *iPad* in Settings.
- **Local network only, no cloud, no telemetry.** Nothing leaves the LAN.
- **Never block Claude Code.** An iPad only extends the existing short "the card
  is on screen" window (800 ms → 2 s) while one is connected; otherwise nothing
  changes. If nobody answers, the terminal asks as usual.
- **Explicit click.** A permission is only approved when someone taps *Allow*
  on the island or on the iPad.

## Pairing

Settings → iPad → *Emparejar iPad* shows a QR code and the same text:

```
voltadock://pair?v=1&n=<desktop name>&p=<port>&h=<host1>,<host2>&k=<key>
```

- `k` is a 32-byte random key, base64url without padding. It is the only
  secret: whoever has it can approve permissions, so it is shown only on
  demand, stored in the Windows Credential Manager / iOS Keychain, and never
  written to disk or logs.
- `h` lists addresses to try in order (LAN IPv4, then `<computer>.local`).
- `p` is the TCP port, 47821 by default.
- *Olvidar iPads* generates a new key: every paired iPad is disconnected and
  must scan again.

## Transport

Plain TCP to `host:port`, then:

1. Handshake, in the clear:
   - iPad → desktop: `"VDR1"` + 32 random bytes (`client_random`)
   - desktop → iPad: `"VDR1"` + 32 random bytes (`server_random`)
2. Keys: `HKDF-SHA256(ikm = key, salt = client_random ‖ server_random,
   info = "voltadock-remote/1", L = 64)`. Bytes 0–31 encrypt iPad → desktop,
   bytes 32–63 desktop → iPad.
3. Frames: `u32 big-endian length` + `ChaCha20-Poly1305(ciphertext ‖ tag)`.
   The nonce is 4 zero bytes + a `u64` big-endian counter, starting at 0 in each
   direction and incremented per frame. No associated data. The plaintext is one
   UTF-8 JSON object. Maximum frame: 1 MiB.
4. Any frame that fails to decrypt closes the connection. Fresh randoms on both
   sides mean a recorded session cannot be replayed.

The first frame from the iPad must be `hello` within 5 seconds. Either side
sends `ping` every 25 s; a connection silent for 90 s is closed.

## Messages

iPad → desktop:

| type       | fields                                   | meaning                                   |
|------------|------------------------------------------|-------------------------------------------|
| `hello`    | `device`, `version`                      | first frame                               |
| `ack`      | `request_id`                             | the approval card is on the iPad screen   |
| `decision` | `request_id`, `decision` (`allow`/`deny`)| a human tapped                            |
| `refresh`  |                                          | send `sessions` again                     |
| `ping`     |                                          | keep-alive                                |

Desktop → iPad:

| type       | fields                                                | meaning                                      |
|------------|-------------------------------------------------------|----------------------------------------------|
| `welcome`  | `host`, `version`, `pending[]`, `sessions[]`          | answer to `hello`: current state             |
| `hook`     | `event` (trimmed Claude Code hook payload)            | every hook event, as the island sees it      |
| `resolved` | `request_id`, `decision` (`allow`/`deny`/`null`)      | a request was answered or went to terminal   |
| `sessions` | `sessions[]` (`id`, `cwd`, `status`, `detail`, `lastSeen`) | recent conversations from the transcripts |
| `ping`     |                                                       | keep-alive                                   |

`event` keeps `hook_event_name`, `session_id`, `cwd`, `request_id`, `tool_name`,
`tool_input`, `prompt`, `message`, `last_assistant_message`,
`notification_type`, `error`, `error_details`; long strings are cut to 2,000
characters.

Permission requests carry `request_id`. Each request is answered once, by
whoever taps first; the other screen gets `resolved` and drops its card.
