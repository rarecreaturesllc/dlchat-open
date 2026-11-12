package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Wire protocol (all POST, all through Tor):
//
//	/v1/queue            body: 32-byte Ed25519 public key (raw)    -> {"recv": hex, "send": hex}
//	/v1/send/{sendID}    body: one envelope (raw bytes)            -> 204
//	/v1/recv/{recvID}    {"ts": unix, "sig": hex, "wait": seconds} -> {"messages": [{"id", "data" (base64)}]}
//	/v1/ack/{recvID}     {"ts", "sig", "ids": [...]}               -> 204
//	/v1/delete/{recvID}  {"ts", "sig"}                             -> 204
//
// Signatures are Ed25519 over "dlchat-relay/v1/<action>|<recvID>|<ts>" with the queue's key.

type signed struct {
	TS   int64    `json:"ts"`
	Sig  string   `json:"sig"`
	Wait int      `json:"wait"`
	IDs  []string `json:"ids"`
}

type envelopeJSON struct {
	ID   string `json:"id"`
	Data string `json:"data"`
}

func SignedMessage(action, recvID string, ts int64) []byte {
	return []byte("dlchat-relay/v1/" + action + "|" + recvID + "|" + strconv.FormatInt(ts, 10))
}

func NewHandler(store *Store, now func() time.Time) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/queue", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "", http.StatusMethodNotAllowed)
			return
		}
		key, err := io.ReadAll(io.LimitReader(r.Body, 64))
		if err != nil || len(key) != ed25519.PublicKeySize {
			http.Error(w, "bad key", http.StatusBadRequest)
			return
		}
		recv, send, err := store.Create(ed25519.PublicKey(key), now())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInsufficientStorage)
			return
		}
		writeJSON(w, map[string]string{"recv": recv, "send": send})
	})
	mux.HandleFunc("/v1/send/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "", http.StatusMethodNotAllowed)
			return
		}
		id := strings.TrimPrefix(r.URL.Path, "/v1/send/")
		data, err := io.ReadAll(io.LimitReader(r.Body, int64(store.limits.MaxEnvelope)+1))
		if err != nil || len(data) == 0 {
			http.Error(w, "bad body", http.StatusBadRequest)
			return
		}
		switch err := store.Put(id, data, now()); {
		case err == nil:
			w.WriteHeader(http.StatusNoContent)
		case errors.Is(err, ErrNoQueue):
			http.Error(w, "", http.StatusNotFound)
		case errors.Is(err, ErrTooLarge):
			http.Error(w, "", http.StatusRequestEntityTooLarge)
		default:
			http.Error(w, err.Error(), http.StatusInsufficientStorage)
		}
	})
	mux.HandleFunc("/v1/recv/", func(w http.ResponseWriter, r *http.Request) {
		id, req, ok := authorize(w, r, store, "recv", now)
		if !ok {
			return
		}
		wait := time.Duration(req.Wait) * time.Second
		if wait > store.limits.MaxLongPoll {
			wait = store.limits.MaxLongPoll
		}
		deadline := time.After(wait)
		for {
			items, ready, err := store.Read(id, now())
			if err != nil {
				http.Error(w, "", http.StatusNotFound)
				return
			}
			if items != nil || wait <= 0 {
				out := make([]envelopeJSON, len(items))
				for i, e := range items {
					out[i] = envelopeJSON{ID: e.ID, Data: base64.StdEncoding.EncodeToString(e.Data)}
				}
				writeJSON(w, map[string]any{"messages": out})
				return
			}
			select {
			case <-ready:
			case <-deadline:
				wait = 0
			case <-r.Context().Done():
				return
			}
		}
	})
	mux.HandleFunc("/v1/ack/", func(w http.ResponseWriter, r *http.Request) {
		id, req, ok := authorize(w, r, store, "ack", now)
		if !ok {
			return
		}
		if store.Ack(id, req.IDs) != nil {
			http.Error(w, "", http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	mux.HandleFunc("/v1/delete/", func(w http.ResponseWriter, r *http.Request) {
		id, _, ok := authorize(w, r, store, "delete", now)
		if !ok {
			return
		}
		if store.Delete(id) != nil {
			http.Error(w, "", http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	return mux
}

func authorize(w http.ResponseWriter, r *http.Request, store *Store, action string, now func() time.Time) (string, signed, bool) {
	var req signed
	if r.Method != http.MethodPost {
		http.Error(w, "", http.StatusMethodNotAllowed)
		return "", req, false
	}
	id := strings.TrimPrefix(r.URL.Path, "/v1/"+action+"/")
	if err := json.NewDecoder(io.LimitReader(r.Body, 64*1024)).Decode(&req); err != nil {
		http.Error(w, "bad body", http.StatusBadRequest)
		return "", req, false
	}
	key, found := store.Key(id)
	sig, err := hex.DecodeString(req.Sig)
	skew := now().Sub(time.Unix(req.TS, 0))
	if skew < 0 {
		skew = -skew
	}
	// Same answer for "no queue" and "bad signature", so ids cannot be probed.
	if !found || err != nil || skew > store.limits.ClockSkew || !ed25519.Verify(key, SignedMessage(action, id, req.TS), sig) {
		http.Error(w, "", http.StatusNotFound)
		return "", req, false
	}
	return id, req, true
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(v)
}
