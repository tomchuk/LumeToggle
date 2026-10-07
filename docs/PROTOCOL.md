# Lume Cube Panel Pro BLE protocol (from Lumecube Android app 2.0.2)

Panel Pro is a Telink "classic" mesh device (not Bluetooth SIG mesh). The app connects to each panel separately.

- Discovery: manufacturer data starts `11 02` (Telink vendor 0x0211). Bytes 4..7 are the low 4 bytes of the MAC. The advertised name is the mesh name: 6 random characters the app assigns when the panel is added.
- Service `00010203-0405-0607-0809-0a0b0c0d1910`. Pair characteristic `…1914`, command characteristic `…1912`, notify characteristic `…1911`.
- Login: write `0C | randm[8] | aes(randm‖0…, name⊕pass)[0:8]` to the pair characteristic, then read it back as `0D | rands[8] | proof[8]`. The session key is `aes(name⊕pass, randm‖rands)`.
- Password: hardcoded `4rfv5tgb`. The Telink factory default is `telink_mesh1` / `123`.
- `aes(k, d)` reverses k and d, runs AES-128-ECB, then reverses the output.
- Command layout (20 bytes, write without response): `seq[3] | mic[2] | enc(dst[2]=0000, op|0xC0, 11 02, params…, pad to 15)`.
  - The IV is `mac4 | 01 | seq[3]`.
  - The MIC and encryption follow `aes_att_encryption_packet` (see `TelinkMesh.swift`).
- Opcodes:
  - `0xD0`: on/off. Params `01 00 00` turn it on, `00 00 00` turn it off.
  - `0xD2`: brightness. Params `[5…100]`.
  - `0xE2`: colour/temperature. Params `04 R G B bri` for colour, `05 temp bri` for temperature.
    - `temp` is 0–100, linear over 3000–5700 K (0 is warm). This is the app's `LCPanelListAdapter.CT_VAL` table: 28 steps of 100 K.
    - The app clamps `bri` to 5–100 here too (`MeshCmdManager.changeTemperature`).
