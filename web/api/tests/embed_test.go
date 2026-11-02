package tests

import (
	"html"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	uiembed "github.com/caritos/stark/embed"
	"github.com/caritos/stark/internal/apptest"
	"github.com/caritos/stark/internal/db/migrations"
	"github.com/caritos/stark/internal/version"
)

// These tests are about the embeds, so they must not skip under -short.

func TestEmbeddedMigrationsPresent(t *testing.T) {
	onDisk, err := filepath.Glob(filepath.Join("..", "internal", "db", "migrations", "*.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if len(onDisk) == 0 {
		t.Fatal("no migrations on disk")
	}
	entries, err := migrations.FS.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	var embedded []string
	for _, e := range entries {
		embedded = append(embedded, e.Name())
	}
	if !sort.StringsAreSorted(embedded) {
		t.Fatalf("embedded migrations not ordered: %v", embedded)
	}
	numbered := regexp.MustCompile(`^\d{4}_[a-z0-9_]+\.sql$`)
	have := map[string]bool{}
	for _, n := range embedded {
		have[n] = true
		if !numbered.MatchString(n) {
			t.Errorf("embedded migration %q is not NNNN_name.sql", n)
		}
	}
	for _, p := range onDisk {
		if !have[filepath.Base(p)] {
			t.Errorf("%s is on disk but not embedded", filepath.Base(p))
		}
	}
	if len(embedded) != len(onDisk) {
		t.Errorf("embedded %d migrations, %d on disk", len(embedded), len(onDisk))
	}
}

// Stark ships no React app (2026-11-01): the binary must not embed a spa/ tree (a stale Vite build in
// web/api/embed/spa would be compiled in by the all:* pattern), and the real server answers /app,
// /app/ and anything under it with the same 404 page as /nope.
func TestNoReactAppEmbeddedAndAppIs404(t *testing.T) {
	if _, err := fs.Stat(uiembed.FS, "spa"); err == nil {
		t.Fatal("the binary embeds web/api/embed/spa (a React build); Stark ships none: run `pnpm build` in web/ (it removes it) or delete web/api/embed/spa")
	}
	a := apptest.NewServer(t)
	_, _, nope := req(t, a.Client, http.MethodGet, a.URL+"/nope", nil, nil)
	for _, p := range []string{"/app", "/app/", "/app/index.html", "/app/notes/1", "/app/assets/index.js"} {
		st, _, body := req(t, a.Client, http.MethodGet, a.URL+p, nil, nil)
		if st != http.StatusNotFound || string(body) != string(nope) {
			t.Errorf("GET %s = %d, same body as /nope: %v; want the 404 page", p, st, string(body) == string(nope))
		}
	}
}

// The frontend files live in web/public; the binary embeds the synced copy under
// embed/. A stale copy (sync-public.sh not run) must fail here, not ship.
func TestEmbeddedPublicFilesMatchWebPublic(t *testing.T) {
	a := apptest.NewServer(t)
	css, err := os.ReadFile(filepath.Join("..", "..", "public", "static", "style.css"))
	if err != nil {
		t.Fatal(err)
	}
	if st, _, body := req(t, a.Client, http.MethodGet, a.URL+"/static/style.css", nil, nil); st != http.StatusOK || string(body) != string(css) {
		t.Fatalf("GET /static/style.css = %d, bytes equal web/public/static/style.css: %v (run web/scripts/sync-public.sh)", st, string(body) == string(css))
	}
	src, err := os.ReadFile(filepath.Join("..", "..", "public", "pages", "privacy.html"))
	if err != nil {
		t.Fatal(err)
	}
	want := strings.ReplaceAll(string(src), "@@BUILD_ID@@", html.EscapeString(version.BuildID))
	if st, _, body := req(t, a.Client, http.MethodGet, a.URL+"/privacy", nil, nil); st != http.StatusOK || string(body) != want {
		t.Fatalf("GET /privacy = %d, equals web/public/pages/privacy.html plus build id: %v (run web/scripts/sync-public.sh)", st, string(body) == want)
	}
}
