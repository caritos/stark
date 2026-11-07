package web

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/caritos/stark/internal/version"
)

func get(h http.Handler, method, target string, hdr ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, nil)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

var (
	h1Re  = regexp.MustCompile(`(?s)<h1[^>]*>\s*([^<\s][^<]*)</h1>`)
	tagRe = regexp.MustCompile(`(?s)<[^>]*>`)
)

func TestPublicPagesHaveBodyText(t *testing.T) {
	h := Handler()
	for _, p := range []string{"/", "/faq", "/privacy", "/terms", "/support"} {
		t.Run(p, func(t *testing.T) {
			rec := get(h, http.MethodGet, p)
			if rec.Code != 200 {
				t.Fatalf("status = %d", rec.Code)
			}
			if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
				t.Fatalf("content-type = %q", ct)
			}
			body := rec.Body.String()
			if !h1Re.MatchString(body) {
				t.Errorf("no non-empty <h1>")
			}
			if !regexp.MustCompile(`(?s)<title>\s*\S`).MatchString(body) {
				t.Errorf("no non-empty <title>")
			}
			if !strings.Contains(body, `href="/static/style.css"`) {
				t.Errorf("does not link shared stylesheet")
			}
			if n := len(strings.TrimSpace(tagRe.ReplaceAllString(body, " "))); n < 200 {
				t.Errorf("only %d bytes of text", n)
			}
			if strings.Contains(body, "{{") || strings.Contains(body, "<script") {
				t.Errorf("template syntax or script found")
			}
		})
	}
}

func TestPrivacyDatedAndMentionsData(t *testing.T) {
	body := get(Handler(), http.MethodGet, "/privacy").Body.String()
	// Stark's policy: dated, says the app collects nothing, where the data lives, and how to ask.
	for _, want := range []string{"LAST UPDATED: NOVEMBER 2026", "CLAUDE CODE BRIDGE", "collects no data", "on your device", "iCloud Backup", "support@caritos.com"} {
		if !strings.Contains(strings.ToLower(body), strings.ToLower(want)) {
			t.Errorf("privacy missing %q", want)
		}
	}
}

func TestStaticETagAndContentLength(t *testing.T) {
	h := Handler()
	rec := get(h, http.MethodGet, "/static/style.css")
	if rec.Code != 200 {
		t.Fatalf("status = %d", rec.Code)
	}
	if !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/css") {
		t.Errorf("content-type = %q", rec.Header().Get("Content-Type"))
	}
	etag := rec.Header().Get("ETag")
	if etag == "" {
		t.Fatal("no ETag")
	}
	if cl := rec.Header().Get("Content-Length"); cl != strconv.Itoa(rec.Body.Len()) || cl == "0" {
		t.Errorf("Content-Length = %q, body %d", cl, rec.Body.Len())
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "no-cache" {
		t.Errorf("Cache-Control = %q", cc)
	}
	rec2 := get(h, http.MethodGet, "/static/style.css", "If-None-Match", etag)
	if rec2.Code != http.StatusNotModified || rec2.Body.Len() != 0 {
		t.Errorf("conditional: status %d body %d", rec2.Code, rec2.Body.Len())
	}
	head := get(h, http.MethodGet, "/", "If-None-Match", get(h, http.MethodGet, "/").Header().Get("ETag"))
	if head.Code != http.StatusNotModified {
		t.Errorf("page conditional status = %d", head.Code)
	}
}

func TestHeadHasLengthNoBody(t *testing.T) {
	rec := get(Handler(), http.MethodHead, "/faq")
	if rec.Code != 200 || rec.Body.Len() != 0 || rec.Header().Get("Content-Length") == "" {
		t.Errorf("status %d body %d CL %q", rec.Code, rec.Body.Len(), rec.Header().Get("Content-Length"))
	}
}

func TestPostRejected(t *testing.T) {
	if rec := get(Handler(), http.MethodPost, "/"); rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d", rec.Code)
	}
}

func TestUnknownIs404HTML(t *testing.T) {
	h := Handler()
	for _, p := range []string{"/nope", "/faq/extra", "/static/missing.css", "/static/"} {
		rec := get(h, http.MethodGet, p)
		if rec.Code != http.StatusNotFound {
			t.Errorf("%s: status = %d", p, rec.Code)
		}
		if !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/html") ||
			!strings.Contains(rec.Body.String(), "Page not found") ||
			!strings.Contains(rec.Body.String(), `href="/"`) {
			t.Errorf("%s: bad 404 body %q", p, rec.Body.String())
		}
	}
}

func TestDefaultHandlerServesTheHomePage(t *testing.T) {
	if rec := get(Handler(), http.MethodGet, "/"); rec.Code != 200 {
		t.Fatalf("/ status = %d", rec.Code)
	}
}

// ---------------------------------------------------------------- build id footer

const testBuildID = "20261027-abc1234"

var pageFiles = func() []string {
	var files []string
	for _, f := range pageRoutes {
		files = append(files, f)
	}
	return files
}()

func TestEveryEmbeddedPageSourceHasTheFooterPlaceholderOnce(t *testing.T) {
	entries, err := content.ReadDir("pages")
	if err != nil {
		t.Fatal(err)
	}
	routed := map[string]bool{}
	for _, f := range pageFiles {
		routed[f] = true
	}
	for _, e := range entries {
		name := "pages/" + e.Name()
		if !routed[name] {
			t.Errorf("%s is embedded but has no route in pageRoutes", name)
		}
		b, err := content.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		src := string(b)
		if n := strings.Count(src, pagePlaceholder); n != 1 {
			t.Errorf("%s contains %q %d times, want exactly 1", name, pagePlaceholder, n)
		}
		if !strings.Contains(src, `<footer class="site-footer">`) || !strings.Contains(src, `class="build-id"`) {
			t.Errorf("%s lacks the site-footer element with a build-id span", name)
		}
	}
}

func TestServedPagesShowTheInjectedBuildID(t *testing.T) {
	h := NewHandlerWithBuildID(testBuildID)
	for route := range pageRoutes {
		body := get(h, http.MethodGet, route).Body.String()
		if !strings.Contains(body, "Build "+testBuildID) {
			t.Errorf("%s: no %q in footer", route, "Build "+testBuildID)
		}
		if strings.Contains(body, pagePlaceholder) {
			t.Errorf("%s: placeholder left in the served page", route)
		}
	}
}

func TestDefaultHandlerUsesVersionBuildID(t *testing.T) {
	body := get(Handler(), http.MethodGet, "/").Body.String()
	if !strings.Contains(body, "Build "+version.BuildID) {
		t.Errorf("home page lacks Build %s", version.BuildID)
	}
	if body2 := get(NewHandlerWithBuildID(version.BuildID), http.MethodGet, "/").Body.String(); body2 != body {
		t.Errorf("NewHandlerWithBuildID and Handler disagree on the home page")
	}
}

func TestPageETagAndLengthFollowTheBuildID(t *testing.T) {
	a := get(NewHandlerWithBuildID("20261027-aaaaaaa"), http.MethodGet, "/faq")
	b := get(NewHandlerWithBuildID("20261028-bbbbbbb"), http.MethodGet, "/faq")
	if a.Header().Get("ETag") == "" || a.Header().Get("ETag") == b.Header().Get("ETag") {
		t.Errorf("ETag does not change with the id: %q vs %q", a.Header().Get("ETag"), b.Header().Get("ETag"))
	}
	if cl := a.Header().Get("Content-Length"); cl != strconv.Itoa(a.Body.Len()) {
		t.Errorf("Content-Length = %q, body %d", cl, a.Body.Len())
	}
}

func TestBuildIDIsHTMLEscaped(t *testing.T) {
	evil := `1"><script>alert(1)</script>&`
	h := NewHandlerWithBuildID(evil)
	for _, p := range []string{"/", "/app/", "/nope"} { // /app/ is the 404 page
		body := get(h, http.MethodGet, p).Body.String()
		if strings.Contains(body, "<script>alert") {
			t.Errorf("%s: unescaped id in %q", p, body)
		}
		if p != "/nope" && !strings.Contains(body, "&lt;script&gt;") && !strings.Contains(body, "&lt;script") {
			t.Errorf("%s: escaped id not present", p)
		}
	}
}

func TestInjectBuildIDReplacesEveryPlaceholderWithoutRescanning(t *testing.T) {
	got := string(injectBuildID([]byte("a @@X@@ b @@X@@"), "@@X@@", "ID"))
	if got != "a ID b ID" {
		t.Errorf("got %q", got)
	}
	if got := string(injectBuildID([]byte("no placeholder"), "@@X@@", "ID")); got != "no placeholder" {
		t.Errorf("got %q", got)
	}
	// the replacement text is never re-scanned
	if got := string(injectBuildID([]byte("@@X@@"), "@@X@@", "@@X@@")); got != "@@X@@" {
		t.Errorf("got %q", got)
	}
}

func TestNotFoundPagesHaveTheFooter(t *testing.T) {
	cases := []struct {
		name, path string
		status     int
	}{
		{"404", "/nope", http.StatusNotFound},
		{"404 under /app/", "/app/assets/nope.js", http.StatusNotFound},
		{"404 /app/", "/app/", http.StatusNotFound},
	}
	for _, c := range cases {
		rec := get(NewHandlerWithBuildID(testBuildID), http.MethodGet, c.path)
		body := rec.Body.String()
		if rec.Code != c.status {
			t.Errorf("%s: status %d", c.name, rec.Code)
		}
		if !strings.Contains(body, `<footer class="site-footer">`) || !strings.Contains(body, `<span class="build-id">Build `+testBuildID+`</span>`) {
			t.Errorf("%s: no footer with the build id in %q", c.name, body)
		}
		if strings.Contains(body, pagePlaceholder) {
			t.Errorf("%s: placeholder left", c.name)
		}
		if cl := rec.Header().Get("Content-Length"); cl != strconv.Itoa(rec.Body.Len()) {
			t.Errorf("%s: Content-Length %q vs body %d", c.name, cl, rec.Body.Len())
		}
		if et := rec.Header().Get("ETag"); et != "" {
			t.Errorf("%s: error page must not carry ETag %q", c.name, et)
		}
	}
}

func TestStaticServesNestedFiles(t *testing.T) {
	h := newHandler(fstest.MapFS{
		"style.css":         {Data: []byte("body{}")},
		"fonts/inter.woff2": {Data: []byte("woff2-bytes")},
		"fonts/deep/y.woff": {Data: []byte("deep")},
	})
	for target, ctype := range map[string]string{
		"/static/style.css":         "text/css",
		"/static/fonts/inter.woff2": "font/woff2",
		"/static/fonts/deep/y.woff": "font/woff",
	} {
		rec := get(h, http.MethodGet, target)
		if rec.Code != 200 || !strings.HasPrefix(rec.Header().Get("Content-Type"), ctype) {
			t.Errorf("%s: status %d, content-type %q", target, rec.Code, rec.Header().Get("Content-Type"))
		}
		if cl := rec.Header().Get("Content-Length"); cl != strconv.Itoa(rec.Body.Len()) || cl == "0" {
			t.Errorf("%s: Content-Length %q, body %d", target, cl, rec.Body.Len())
		}
		if rec.Header().Get("ETag") == "" {
			t.Errorf("%s: no ETag", target)
		}
	}
	// A directory, a missing file and traversal are never served as a listing or a file outside static/.
	for _, target := range []string{"/static/fonts", "/static/fonts/", "/static/fonts/missing.woff2", "/static/", "/static/fonts/../../web.go"} {
		if rec := get(h, http.MethodGet, target); rec.Code == 200 {
			t.Errorf("%s: got 200, want 404 or a redirect", target)
		}
	}
}

func TestRequireUITellsHowToBuildWhenEmpty(t *testing.T) {
	err := requireUI(fstest.MapFS{".gitkeep": {}})
	if err == nil || !strings.Contains(err.Error(), "pnpm build") || !strings.Contains(err.Error(), "web/scripts/sync-public.sh") {
		t.Fatalf("requireUI(empty) = %v, want an error naming pnpm build and web/scripts/sync-public.sh", err)
	}
	if err := requireUI(fstest.MapFS{"pages/index.html": {Data: []byte("x")}}); err != nil {
		t.Fatalf("requireUI(with pages) = %v", err)
	}
}

func TestStaticSkipsHiddenFiles(t *testing.T) {
	h := newHandler(fstest.MapFS{
		"style.css":   {Data: []byte("body{}")},
		".DS_Store":   {Data: []byte("junk")},
		"fonts/.nope": {Data: []byte("junk")},
	})
	for _, target := range []string{"/static/.DS_Store", "/static/fonts/.nope"} {
		if rec := get(h, http.MethodGet, target); rec.Code != http.StatusNotFound {
			t.Errorf("%s: got %d, want 404", target, rec.Code)
		}
	}
	if rec := get(h, http.MethodGet, "/static/style.css"); rec.Code != http.StatusOK {
		t.Errorf("style.css: got %d", rec.Code)
	}
}

func TestEtagMatchesForms(t *testing.T) {
	const tag = `"abc123"`
	for _, tc := range []struct {
		header string
		want   bool
	}{
		{tag, true},
		{`W/` + tag, true},
		{`"other", ` + tag, true},
		{`"other" ,  ` + tag + ` , "third"`, true},
		{"*", true},
		{`"other"`, false},
		{`abc123`, false}, // unquoted is not a valid entity-tag
		{"", false},
		{`,`, false},
	} {
		if got := etagMatches(tc.header, tag); got != tc.want {
			t.Errorf("etagMatches(%q) = %v, want %v", tc.header, got, tc.want)
		}
	}
}

func TestHeadWithMatchingIfNoneMatchIs304WithoutBody(t *testing.T) {
	h := Handler()
	etag := get(h, http.MethodGet, "/faq").Header().Get("ETag")
	rec := get(h, http.MethodHead, "/faq", "If-None-Match", etag)
	if rec.Code != http.StatusNotModified || rec.Body.Len() != 0 {
		t.Errorf("status %d, body %d", rec.Code, rec.Body.Len())
	}
}

func TestErrorPagesHaveContentLengthAndNoETag(t *testing.T) {
	for name, rec := range map[string]*httptest.ResponseRecorder{
		"404":      get(Handler(), http.MethodGet, "/nope"),
		"404 /app": get(Handler(), http.MethodGet, "/app"),
	} {
		if cl := rec.Header().Get("Content-Length"); cl != strconv.Itoa(rec.Body.Len()) || cl == "0" {
			t.Errorf("%s: Content-Length %q, body %d", name, cl, rec.Body.Len())
		}
		if et := rec.Header().Get("ETag"); et != "" {
			t.Errorf("%s: error page must not carry ETag %q", name, et)
		}
	}
}

func TestNestedStaticAssetsAreServedUnmodifiedWithTheBuildID(t *testing.T) {
	h := newHandlerWithBuildID(fstest.MapFS{
		"style.css":         {Data: []byte("/* @@BUILD_ID@@ __BUILD_ID__ */")},
		"fonts/inter.woff2": {Data: []byte("woff2 @@BUILD_ID@@")},
	}, testBuildID)
	for p, want := range map[string]string{
		"/static/style.css":         "/* @@BUILD_ID@@ __BUILD_ID__ */",
		"/static/fonts/inter.woff2": "woff2 @@BUILD_ID@@",
	} {
		if got := get(h, http.MethodGet, p).Body.String(); got != want {
			t.Errorf("%s was modified: %q", p, got)
		}
	}
	for _, p := range []string{"/", "/nope"} {
		if body := get(h, http.MethodGet, p).Body.String(); !strings.Contains(body, "Build "+testBuildID) {
			t.Errorf("%s: no build id in the footer", p)
		}
	}
	if body := get(newHandler(fstest.MapFS{}), http.MethodGet, "/").Body.String(); !strings.Contains(body, "Build "+version.BuildID) {
		t.Errorf("newHandler does not use version.BuildID")
	}
}

// A public page asked for with a trailing slash ("/terms/", typed by habit or added by a link)
// is a 301 to the slash-free page, keeping the query. The Location is relative (a path), so
// behind a TLS-terminating proxy the browser keeps the https scheme it used. Anything that is
// not a page with a slash added is not redirected.
func TestPageWithTrailingSlashRedirects(t *testing.T) {
	h := Handler()
	for _, tc := range []struct{ target, want string }{
		{"/terms/", "/terms"},
		{"/faq/", "/faq"},
		{"/privacy/", "/privacy"},
		{"/support/?ref=x", "/support?ref=x"},
	} {
		rec := get(h, http.MethodGet, tc.target)
		if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != tc.want {
			t.Errorf("GET %s = %d Location %q, want 301 %q", tc.target, rec.Code, rec.Header().Get("Location"), tc.want)
		}
	}
	if rec := get(h, http.MethodHead, "/terms/"); rec.Code != http.StatusMovedPermanently {
		t.Errorf("HEAD /terms/ = %d, want 301", rec.Code)
	}
	for _, p := range []string{"/nope/", "/static/style.css/", "//"} {
		if rec := get(h, http.MethodGet, p); rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", p, rec.Code)
		}
	}
	if rec := get(h, http.MethodGet, "/"); rec.Code != http.StatusOK {
		t.Errorf("GET / = %d, want 200", rec.Code)
	}
}

// Stark ships no React app (2026-11-01): /app, /app/ and anything under it are the ordinary 404
// page, byte for byte the same as /nope, never a redirect, an SPA index or an asset.
func TestAppPathsAreThe404Page(t *testing.T) {
	h := Handler()
	nope := get(h, http.MethodGet, "/nope")
	for _, p := range []string{"/app", "/app/", "/app/index.html", "/app/notes/1", "/app/assets/index-abc.js", "/app/favicon.svg", "/app/login"} {
		rec := get(h, http.MethodGet, p)
		if rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", p, rec.Code)
		}
		if rec.Body.String() != nope.Body.String() {
			t.Errorf("GET %s: body is not the 404 page: %q", p, rec.Body.String())
		}
		if loc := rec.Header().Get("Location"); loc != "" {
			t.Errorf("GET %s: Location %q, want none", p, loc)
		}
	}
}
