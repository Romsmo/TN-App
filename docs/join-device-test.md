# Join code: test on the device (the owner runs it; nothing here has been run yet)

Needs the server from branch `feat/join-code` (server 1.3.0) with a public address, and its page "App verbinden".

1. Open the page on a second screen. Note the fingerprint shown there.
2. App: Settings → Connect to server → *Scan code*. Allow the camera. Scan. The confirmation shows the address and the same
   fingerprint. Tap *Connect*. Expect: status "Online", reports appear.
3. *Paste code* with the text from the page. Expect the same confirmation.
4. Open the code as a link (type `trafficnetwork://join?…` into Notes and tap it, or scan with the system camera). Expect the
   confirmation, also when the app was closed.
5. A revoked code (`join:revoke`): expect the text "Der Code wurde widerrufen…" in the status card.
6. Restart the app: still connected. *Disconnect server*: back in emergency mode, nothing stored.
7. Scan something that is not a join code: expect "Das ist kein Verbindungscode.", nothing connects.
8. While driving (or in the simulation preview) the confirmation is locked.
