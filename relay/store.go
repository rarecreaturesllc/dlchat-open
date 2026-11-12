package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/gob"
	"encoding/hex"
	"errors"
	"os"
	"sync"
	"time"
)

// Limits keep one queue (or one abuser) from filling the relay.
type Limits struct {
	MaxEnvelope  int           // bytes per envelope
	MaxPerQueue  int           // envelopes waiting in one queue
	MaxQueues    int           // queues on this relay
	MaxBytes     int64         // all envelopes together
	EnvelopeTTL  time.Duration // unread envelopes are dropped after this
	QueueIdleTTL time.Duration // a queue nobody reads is dropped after this
	ClockSkew    time.Duration // signed requests must be this close to the relay's clock
	MaxLongPoll  time.Duration
}

func DefaultLimits() Limits {
	return Limits{
		MaxEnvelope:  32 * 1024,
		MaxPerQueue:  1000,
		MaxQueues:    200_000,
		MaxBytes:     2 << 30,
		EnvelopeTTL:  14 * 24 * time.Hour,
		QueueIdleTTL: 60 * 24 * time.Hour,
		ClockSkew:    10 * time.Minute,
		MaxLongPoll:  25 * time.Second,
	}
}

var (
	ErrNoQueue   = errors.New("no such queue")
	ErrFull      = errors.New("queue full")
	ErrTooLarge  = errors.New("envelope too large")
	ErrRelayFull = errors.New("relay full")
)

type Envelope struct {
	ID   string
	Data []byte
	At   time.Time
}

type Queue struct {
	RecvID   string
	SendID   string
	Key      []byte // Ed25519 public key of the reader
	Items    []Envelope
	LastRead time.Time
}

type Store struct {
	mu      sync.Mutex
	limits  Limits
	byRecv  map[string]*Queue
	bySend  map[string]*Queue
	bytes   int64
	waiters map[string][]chan struct{}
}

func NewStore(l Limits) *Store {
	return &Store{limits: l, byRecv: map[string]*Queue{}, bySend: map[string]*Queue{}, waiters: map[string][]chan struct{}{}}
}

func randomID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// Create makes a queue read with `key` and returns its receive and send ids.
func (s *Store) Create(key ed25519.PublicKey, now time.Time) (recv, send string, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.byRecv) >= s.limits.MaxQueues {
		return "", "", ErrRelayFull
	}
	q := &Queue{RecvID: randomID(), SendID: randomID(), Key: append([]byte(nil), key...), LastRead: now}
	s.byRecv[q.RecvID] = q
	s.bySend[q.SendID] = q
	return q.RecvID, q.SendID, nil
}

// Put drops an envelope into the queue with this send id.
func (s *Store) Put(sendID string, data []byte, now time.Time) error {
	if len(data) > s.limits.MaxEnvelope {
		return ErrTooLarge
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	q := s.bySend[sendID]
	if q == nil {
		return ErrNoQueue
	}
	if len(q.Items) >= s.limits.MaxPerQueue {
		return ErrFull
	}
	if s.bytes+int64(len(data)) > s.limits.MaxBytes {
		return ErrRelayFull
	}
	q.Items = append(q.Items, Envelope{ID: randomID(), Data: append([]byte(nil), data...), At: now})
	s.bytes += int64(len(data))
	for _, w := range s.waiters[q.RecvID] {
		close(w)
	}
	delete(s.waiters, q.RecvID)
	return nil
}

// Key returns the reader key of a queue.
func (s *Store) Key(recvID string) (ed25519.PublicKey, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	q := s.byRecv[recvID]
	if q == nil {
		return nil, false
	}
	return q.Key, true
}

// Read returns waiting envelopes, or a channel closed when one arrives.
func (s *Store) Read(recvID string, now time.Time) ([]Envelope, <-chan struct{}, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	q := s.byRecv[recvID]
	if q == nil {
		return nil, nil, ErrNoQueue
	}
	q.LastRead = now
	if len(q.Items) > 0 {
		out := make([]Envelope, len(q.Items))
		copy(out, q.Items)
		return out, nil, nil
	}
	w := make(chan struct{})
	s.waiters[recvID] = append(s.waiters[recvID], w)
	return nil, w, nil
}

// Ack deletes envelopes the reader has stored.
func (s *Store) Ack(recvID string, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	q := s.byRecv[recvID]
	if q == nil {
		return ErrNoQueue
	}
	drop := map[string]bool{}
	for _, id := range ids {
		drop[id] = true
	}
	kept := q.Items[:0]
	for _, e := range q.Items {
		if drop[e.ID] {
			s.bytes -= int64(len(e.Data))
			continue
		}
		kept = append(kept, e)
	}
	q.Items = kept
	return nil
}

// Delete removes a queue and everything in it.
func (s *Store) Delete(recvID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	q := s.byRecv[recvID]
	if q == nil {
		return ErrNoQueue
	}
	s.drop(q)
	return nil
}

func (s *Store) drop(q *Queue) {
	for _, e := range q.Items {
		s.bytes -= int64(len(e.Data))
	}
	delete(s.byRecv, q.RecvID)
	delete(s.bySend, q.SendID)
	for _, w := range s.waiters[q.RecvID] {
		close(w)
	}
	delete(s.waiters, q.RecvID)
}

// Prune drops old envelopes and idle queues.
func (s *Store) Prune(now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, q := range s.byRecv {
		if now.Sub(q.LastRead) > s.limits.QueueIdleTTL {
			s.drop(q)
			continue
		}
		kept := q.Items[:0]
		for _, e := range q.Items {
			if now.Sub(e.At) > s.limits.EnvelopeTTL {
				s.bytes -= int64(len(e.Data))
				continue
			}
			kept = append(kept, e)
		}
		q.Items = kept
	}
}

// Counts for tests.
func (s *Store) Counts() (queues int, envelopes int, bytes int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, q := range s.byRecv {
		envelopes += len(q.Items)
	}
	return len(s.byRecv), envelopes, s.bytes
}

// Save writes the queues to `path` (owner-only permissions), replacing it atomically.
func (s *Store) Save(path string) error {
	s.mu.Lock()
	queues := make([]Queue, 0, len(s.byRecv))
	for _, q := range s.byRecv {
		queues = append(queues, *q)
	}
	s.mu.Unlock()
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if err := gob.NewEncoder(f).Encode(queues); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func (s *Store) Load(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	var queues []Queue
	if err := gob.NewDecoder(f).Decode(&queues); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range queues {
		q := queues[i]
		s.byRecv[q.RecvID] = &q
		s.bySend[q.SendID] = &q
		for _, e := range q.Items {
			s.bytes += int64(len(e.Data))
		}
	}
	return nil
}
