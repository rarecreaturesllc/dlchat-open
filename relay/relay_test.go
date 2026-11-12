package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

type client struct {
	t    *testing.T
	url  string
	priv ed25519.PrivateKey
	now  func() time.Time
}

func (c client) post(path string, body []byte) *http.Response {
	resp, err := http.Post(c.url+path, "application/octet-stream", bytes.NewReader(body))
	if err != nil {
		c.t.Fatal(err)
	}
	return resp
}

func (c client) signedBody(action, recv string, extra map[string]any) []byte {
	ts := c.now().Unix()
	m := map[string]any{"ts": ts, "sig": hex.EncodeToString(ed25519.Sign(c.priv, SignedMessage(action, recv, ts)))}
	for k, v := range extra {
		m[k] = v
	}
	b, _ := json.Marshal(m)
	return b
}

func setup(t *testing.T) (client, *Store, func()) {
	store := NewStore(DefaultLimits())
	clock := time.Unix(1_800_000_000, 0)
	server := httptest.NewServer(NewHandler(store, func() time.Time { return clock }))
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	return client{t: t, url: server.URL, priv: priv, now: func() time.Time { return clock }}, store, server.Close
}

func (c client) create() (recv, send string) {
	resp := c.post("/v1/queue", c.priv.Public().(ed25519.PublicKey))
	if resp.StatusCode != 200 {
		c.t.Fatalf("create: %d", resp.StatusCode)
	}
	var ids map[string]string
	json.NewDecoder(resp.Body).Decode(&ids)
	return ids["recv"], ids["send"]
}

func (c client) read(recv string, wait int) (int, []envelopeJSON) {
	resp := c.post("/v1/recv/"+recv, c.signedBody("recv", recv, map[string]any{"wait": wait}))
	var out struct{ Messages []envelopeJSON }
	json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out.Messages
}

func TestSendReadAckDelete(t *testing.T) {
	c, store, done := setup(t)
	defer done()
	recv, send := c.create()
	if recv == send || len(recv) != 32 || len(send) != 32 {
		t.Fatalf("ids %q %q", recv, send)
	}
	for _, m := range []string{"one", "two"} {
		if r := c.post("/v1/send/"+send, []byte(m)); r.StatusCode != 204 {
			t.Fatalf("send %d", r.StatusCode)
		}
	}
	status, msgs := c.read(recv, 0)
	if status != 200 || len(msgs) != 2 {
		t.Fatalf("read %d %v", status, msgs)
	}
	got, _ := base64.StdEncoding.DecodeString(msgs[0].Data)
	if string(got) != "one" {
		t.Fatalf("first %q", got)
	}
	if r := c.post("/v1/ack/"+recv, c.signedBody("ack", recv, map[string]any{"ids": []string{msgs[0].ID}})); r.StatusCode != 204 {
		t.Fatalf("ack %d", r.StatusCode)
	}
	_, msgs = c.read(recv, 0)
	if len(msgs) != 1 {
		t.Fatalf("after ack %d", len(msgs))
	}
	if r := c.post("/v1/delete/"+recv, c.signedBody("delete", recv, nil)); r.StatusCode != 204 {
		t.Fatalf("delete %d", r.StatusCode)
	}
	if q, e, b := store.Counts(); q != 0 || e != 0 || b != 0 {
		t.Fatalf("left %d %d %d", q, e, b)
	}
	if r := c.post("/v1/send/"+send, []byte("x")); r.StatusCode != 404 {
		t.Fatalf("send to deleted %d", r.StatusCode)
	}
}

func TestSendIDCannotRead(t *testing.T) {
	c, _, done := setup(t)
	defer done()
	_, send := c.create()
	if status, _ := c.read(send, 0); status != 404 {
		t.Fatalf("read by send id: %d", status)
	}
}

func TestWrongKeyAndOldSignatureRefused(t *testing.T) {
	c, _, done := setup(t)
	defer done()
	recv, send := c.create()
	c.post("/v1/send/"+send, []byte("secret"))
	_, other, _ := ed25519.GenerateKey(rand.Reader)
	stranger := client{t: t, url: c.url, priv: other, now: c.now}
	if status, _ := stranger.read(recv, 0); status != 404 {
		t.Fatalf("stranger read %d", status)
	}
	stale := client{t: t, url: c.url, priv: c.priv, now: func() time.Time { return c.now().Add(-time.Hour) }}
	if status, _ := stale.read(recv, 0); status != 404 {
		t.Fatalf("stale read %d", status)
	}
	// Signature for a different action does not work either.
	ts := c.now().Unix()
	body, _ := json.Marshal(map[string]any{"ts": ts, "sig": hex.EncodeToString(ed25519.Sign(c.priv, SignedMessage("recv", recv, ts)))})
	if r := c.post("/v1/delete/"+recv, body); r.StatusCode != 404 {
		t.Fatalf("cross-action %d", r.StatusCode)
	}
}

func TestLongPollWakesOnArrival(t *testing.T) {
	c, _, done := setup(t)
	defer done()
	recv, send := c.create()
	go func() {
		time.Sleep(200 * time.Millisecond)
		c.post("/v1/send/"+send, []byte("late"))
	}()
	start := time.Now()
	status, msgs := c.read(recv, 5)
	if status != 200 || len(msgs) != 1 || time.Since(start) > 4*time.Second {
		t.Fatalf("long poll %d %d %v", status, len(msgs), time.Since(start))
	}
}

func TestLimitsAndPrune(t *testing.T) {
	store := NewStore(DefaultLimits())
	store.limits.MaxPerQueue = 2
	now := time.Unix(1_800_000_000, 0)
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	recv, send, _ := store.Create(priv.Public().(ed25519.PublicKey), now)
	if store.Put(send, make([]byte, store.limits.MaxEnvelope+1), now) != ErrTooLarge {
		t.Fatal("too large accepted")
	}
	store.Put(send, []byte("a"), now)
	store.Put(send, []byte("b"), now)
	if store.Put(send, []byte("c"), now) != ErrFull {
		t.Fatal("full queue accepted")
	}
	store.Prune(now.Add(15 * 24 * time.Hour))
	if _, e, b := store.Counts(); e != 0 || b != 0 {
		t.Fatalf("old envelopes kept %d %d", e, b)
	}
	store.Prune(now.Add(61 * 24 * time.Hour))
	if q, _, _ := store.Counts(); q != 0 {
		t.Fatal("idle queue kept")
	}
	_ = recv
}

func TestSaveAndLoad(t *testing.T) {
	store := NewStore(DefaultLimits())
	now := time.Now()
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	recv, send, _ := store.Create(priv.Public().(ed25519.PublicKey), now)
	store.Put(send, []byte("kept"), now)
	path := t.TempDir() + "/relay.gob"
	if err := store.Save(path); err != nil {
		t.Fatal(err)
	}
	again := NewStore(DefaultLimits())
	if err := again.Load(path); err != nil {
		t.Fatal(err)
	}
	items, _, err := again.Read(recv, now)
	if err != nil || len(items) != 1 || string(items[0].Data) != "kept" {
		t.Fatalf("reload %v %v", items, err)
	}
}
