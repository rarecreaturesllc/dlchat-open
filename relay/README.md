# dlchat-relay

The private mailbox relay behind DLChat's Internet Messages route B ("Private relays").
Standard library Go only; it runs behind a Tor onion service and never sees an IP address.

What it stores: one-way queues of envelopes that are already end-to-end encrypted on the phone
(post-quantum Double Ratchet, then padded and sealed again per contact). It never holds keys,
names, phone numbers or contact lists. Envelopes are deleted when the phone acknowledges them,
or after 14 days; queues nobody reads go after 60 days.

## Test

    go test ./...

## Build

    GOOS=linux GOARCH=amd64 go build -trimpath -o dlchat-relay .   # most servers
    GOOS=linux GOARCH=arm64 go build -trimpath -o dlchat-relay .   # ARM servers

## Deploy (needs the owner's go-ahead: it is a production server)

    scp -r relay root@SERVER:/root/
    ssh root@SERVER sh /root/relay/deploy/setup.sh

The script prints the onion address. Put it (as `http://<address>.onion`) in
`DirectModel.defaultPrivateRelays` in the app, or in Settings > Internet Messaging > Private relays.

## Run locally (Simulator testing, Tor off)

    go run . -listen 127.0.0.1:8080

and launch the app with `-direct-relay http://127.0.0.1:8080 -no-tor`.
