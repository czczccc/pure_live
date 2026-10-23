package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

const testToken = "0123456789abcdef"

func newTestServer(t *testing.T) http.Handler {
	t.Helper()
	db, err := openDB(filepath.Join(t.TempDir(), "sync.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return (&server{db: db, token: testToken}).routes()
}

func doSync(t *testing.T, h http.Handler, token string, req syncRequest) (int, syncResponse) {
	t.Helper()
	body, _ := json.Marshal(req)
	r := httptest.NewRequest(http.MethodPost, "/api/v1/sync", bytes.NewReader(body))
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	var resp syncResponse
	if w.Code == http.StatusOK {
		if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
			t.Fatal(err)
		}
	}
	return w.Code, resp
}

func TestRejectsWrongToken(t *testing.T) {
	h := newTestServer(t)
	if code, _ := doSync(t, h, "wrong-token-value", syncRequest{}); code != http.StatusUnauthorized {
		t.Fatalf("code = %d, want 401", code)
	}
}

func TestNewerWriteWinsAndCursorAdvances(t *testing.T) {
	h := newTestServer(t)
	_, first := doSync(t, h, testToken, syncRequest{Changes: []record{
		{Collection: "favorite", Key: "huya:1", Data: json.RawMessage(`{"v":1}`), UpdatedAt: 100},
	}})
	if len(first.Changes) != 1 || first.Cursor == 0 {
		t.Fatalf("first sync = %+v", first)
	}

	// An older write from another device must not replace the newer value.
	_, stale := doSync(t, h, testToken, syncRequest{Since: first.Cursor, Changes: []record{
		{Collection: "favorite", Key: "huya:1", Data: json.RawMessage(`{"v":0}`), UpdatedAt: 50},
	}})
	if len(stale.Changes) != 0 {
		t.Fatalf("stale write was stored: %+v", stale)
	}

	_, del := doSync(t, h, testToken, syncRequest{Since: first.Cursor, Changes: []record{
		{Collection: "favorite", Key: "huya:1", Deleted: true, UpdatedAt: 200},
	}})
	if len(del.Changes) != 1 || !del.Changes[0].Deleted || del.Changes[0].Data != nil {
		t.Fatalf("tombstone = %+v", del)
	}

	_, all := doSync(t, h, testToken, syncRequest{})
	if len(all.Changes) != 1 || !all.Changes[0].Deleted {
		t.Fatalf("full pull = %+v", all)
	}
}
