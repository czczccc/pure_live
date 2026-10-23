// Command syncserver stores Pure Live records so several devices of one user
// share follows, tags, shield lists, history and settings.
//
// Each record is identified by (collection, key) and carries the client
// timestamp of its last change. The newer timestamp wins; deletions are kept
// as tombstones so they reach devices that were offline when they happened.
package main

import (
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"

	_ "modernc.org/sqlite"
)

const maxBodyBytes = 32 << 20

type record struct {
	Collection string          `json:"collection"`
	Key        string          `json:"key"`
	Data       json.RawMessage `json:"data,omitempty"`
	Deleted    bool            `json:"deleted"`
	UpdatedAt  int64           `json:"updatedAt"`
}

type syncRequest struct {
	Since   int64    `json:"since"`
	Changes []record `json:"changes"`
}

type syncResponse struct {
	Cursor  int64    `json:"cursor"`
	Changes []record `json:"changes"`
}

type server struct {
	db    *sql.DB
	token string
}

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS records (
		collection TEXT NOT NULL,
		key        TEXT NOT NULL,
		data       TEXT,
		deleted    INTEGER NOT NULL DEFAULT 0,
		updated_at INTEGER NOT NULL,
		seq        INTEGER NOT NULL,
		PRIMARY KEY (collection, key)
	);
	CREATE INDEX IF NOT EXISTS records_seq ON records(seq);`)
	if err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func (s *server) authorized(r *http.Request) bool {
	got, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	return ok && subtle.ConstantTimeCompare([]byte(got), []byte(s.token)) == 1
}

// apply stores the incoming changes and returns every record whose sequence
// is newer than since, including the ones just written.
func (s *server) apply(req syncRequest) (syncResponse, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return syncResponse{}, err
	}
	defer tx.Rollback()

	var seq int64
	if err := tx.QueryRow(`SELECT COALESCE(MAX(seq), 0) FROM records`).Scan(&seq); err != nil {
		return syncResponse{}, err
	}
	for _, c := range req.Changes {
		if c.Collection == "" || c.Key == "" {
			return syncResponse{}, errors.New("collection and key are required")
		}
		data := sql.NullString{String: string(c.Data), Valid: !c.Deleted && len(c.Data) > 0}
		seq++
		// Older writes lose; equal timestamps keep the stored value so a
		// replayed request is a no-op.
		_, err := tx.Exec(`INSERT INTO records (collection, key, data, deleted, updated_at, seq)
			VALUES (?, ?, ?, ?, ?, ?)
			ON CONFLICT(collection, key) DO UPDATE SET
				data = excluded.data, deleted = excluded.deleted,
				updated_at = excluded.updated_at, seq = excluded.seq
			WHERE excluded.updated_at > records.updated_at`,
			c.Collection, c.Key, data, c.Deleted, c.UpdatedAt, seq)
		if err != nil {
			return syncResponse{}, err
		}
	}

	rows, err := tx.Query(`SELECT collection, key, data, deleted, updated_at, seq
		FROM records WHERE seq > ? ORDER BY seq`, req.Since)
	if err != nil {
		return syncResponse{}, err
	}
	resp := syncResponse{Cursor: req.Since, Changes: []record{}}
	for rows.Next() {
		var rec record
		var data sql.NullString
		var rowSeq int64
		if err := rows.Scan(&rec.Collection, &rec.Key, &data, &rec.Deleted, &rec.UpdatedAt, &rowSeq); err != nil {
			rows.Close()
			return syncResponse{}, err
		}
		if data.Valid {
			rec.Data = json.RawMessage(data.String)
		}
		resp.Changes = append(resp.Changes, rec)
		resp.Cursor = rowSeq
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return syncResponse{}, err
	}
	return resp, tx.Commit()
}

func (s *server) handleSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !s.authorized(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var req syncRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes)).Decode(&req); err != nil {
		http.Error(w, "bad request: "+err.Error(), http.StatusBadRequest)
		return
	}
	resp, err := s.apply(req)
	if err != nil {
		log.Printf("sync failed: %v", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/sync", s.handleSync)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	return mux
}

func main() {
	token := os.Getenv("SYNC_TOKEN")
	if len(token) < 16 {
		log.Fatal("SYNC_TOKEN must be set to at least 16 characters")
	}
	dbPath := os.Getenv("SYNC_DB")
	if dbPath == "" {
		dbPath = "/data/sync.db"
	}
	addr := os.Getenv("SYNC_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	db, err := openDB(dbPath)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	s := &server{db: db, token: token}
	log.Printf("pure live sync server listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, s.routes()))
}
