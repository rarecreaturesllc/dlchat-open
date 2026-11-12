// dlchat-relay: the private mailbox relay for DLChat Internet Messages (route B).
//
// It is meant to run only behind a Tor onion service (see deploy/), listening on 127.0.0.1.
// It stores opaque, already end-to-end encrypted envelopes in one-way queues:
//
//   - a phone creates a queue and gets two random ids: a receive id (kept) and a send id (given
//     to one contact). The relay cannot link the two ends to people, and never sees an IP address
//     (all clients arrive through Tor).
//   - anyone holding the send id can drop an envelope in; only the holder of the queue's Ed25519
//     key can read and delete them (every read or delete is signed).
//   - envelopes are deleted once acknowledged, or after 14 days; idle queues after 60 days.
//
// There is no logging of requests, no accounts, no cookies and no third-party code (Go standard
// library only).
package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:8080", "address to listen on (keep it on loopback; Tor forwards to it)")
	data := flag.String("data", "", "file to keep queues in across restarts (empty: memory only)")
	flag.Parse()

	store := NewStore(DefaultLimits())
	if *data != "" {
		if err := store.Load(*data); err != nil && !os.IsNotExist(err) {
			log.Fatalf("load %s: %v", *data, err)
		}
	}
	server := &http.Server{
		Addr:              *listen,
		Handler:           NewHandler(store, time.Now),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      40 * time.Second, // long polls wait up to 25 s
		IdleTimeout:       60 * time.Second,
		ErrorLog:          log.New(discard{}, "", 0), // no per-request logging
	}

	go func() {
		for range time.Tick(time.Minute) {
			store.Prune(time.Now())
			if *data != "" {
				if err := store.Save(*data); err != nil {
					log.Printf("save: %v", err)
				}
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		if *data != "" {
			_ = store.Save(*data)
		}
		os.Exit(0)
	}()

	log.Printf("dlchat-relay listening on %s", *listen)
	log.Fatal(server.ListenAndServe())
}

type discard struct{}

func (discard) Write(p []byte) (int, error) { return len(p), nil }
