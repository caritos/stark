// Package web serves the embedded public pages and static files. Everything is embedded with
// go:embed so the release is one binary. Stark ships no React app (2026-11-01): the starter's
// /app/ mount was removed, so /app and everything under it is the ordinary 404 page.
package web

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"html"
	"io/fs"
	"mime"
	"net/http"
	"path"
	"strconv"
	"strings"

	uiembed "github.com/caritos/stark/embed"
	"github.com/caritos/stark/internal/version"
)

// content is the embedded UI tree: pages/ and static/ (see package embed).
var content = uiembed.FS

const cacheRevalidate = "no-cache"

// pageRoutes maps public URL paths to files in the embedded pages/.
var pageRoutes = map[string]string{
	"/":        "pages/index.html",
	"/faq":     "pages/faq.html",
	"/privacy": "pages/privacy.html",
	"/terms":   "pages/terms.html",
	"/support": "pages/support.html",
}

// pagePlaceholder marks where the build id goes in every page source under pages/
// and in the generated 404 page. It is replaced once, at startup.
const pagePlaceholder = "@@BUILD_ID@@"

// footerHTML is the footer of the pages generated in Go; the static pages carry the same
// markup in their source files.
const footerHTML = `<footer class="site-footer"><p><span class="build-id">Build ` + pagePlaceholder + `</span></p></footer>`

var notFoundHTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Page not found</title><link rel="stylesheet" href="/static/style.css"></head>
<body><main><h1>Page not found</h1><p>We could not find that page. <a href="/">Go to the home page</a>.</p></main>
` + footerHTML + `</body></html>
`

type handler struct {
	pages    map[string]asset // by URL path
	static   map[string]asset // by URL path
	notFound asset
}

type asset struct {
	body  []byte
	ctype string
	etag  string
}

// Handler serves the public site and /static/* from the embedded files.
func Handler() http.Handler { return NewHandlerWithBuildID(version.BuildID) }

// injectBuildID returns b with every occurrence of placeholder replaced by id,
// HTML-escaped (the id comes from -ldflags, but it ends up inside markup). It is the only
// templating in this package and the replacement is not re-scanned. The page sources hold
// the placeholder exactly once (a test enforces it).
func injectBuildID(b []byte, placeholder, id string) []byte {
	return bytes.Replace(b, []byte(placeholder), []byte(html.EscapeString(id)), -1)
}

// NewHandlerWithBuildID is Handler with an explicit build id, which is substituted once
// (before ETags and lengths are computed) into the page footers and the 404 page.
func NewHandlerWithBuildID(buildID string) http.Handler {
	static, err := fs.Sub(content, "static")
	if err != nil {
		panic(err) // the embed directive guarantees static/ exists
	}
	return newHandlerWithBuildID(static, buildID)
}

// newHandler also takes the static tree (rooted at static/, subfolders such as
// fonts/ included) so tests can inject one.
func newHandler(static fs.FS) http.Handler {
	return newHandlerWithBuildID(static, version.BuildID)
}

// newHandlerWithBuildID is the constructor behind all of the above. Static files are served
// byte for byte; only the pages and the generated 404 page get the build id.
func newHandlerWithBuildID(static fs.FS, buildID string) http.Handler {
	if err := requireUI(content); err != nil {
		panic(err)
	}
	h := &handler{pages: map[string]asset{}, static: map[string]asset{}}
	for route, file := range pageRoutes {
		h.pages[route] = mustLoad(file, buildID)
	}
	h.notFound = errorPage(injectBuildID([]byte(notFoundHTML), pagePlaceholder, buildID))
	err := fs.WalkDir(static, ".", func(name string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if strings.HasPrefix(d.Name(), ".") && name != "." { // .DS_Store and friends are never served
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			return nil
		}
		b, err := fs.ReadFile(static, name)
		if err != nil {
			return err
		}
		h.static["/static/"+name] = newAsset(name, b)
		return nil
	})
	if err != nil {
		panic(err)
	}
	return h
}

// requireUI fails when the embedded UI tree holds no pages. The tree is generated from
// web/public (go:embed cannot reach outside the Go module), so an empty one means the build was
// skipped; serving a site with nothing in it, or failing later with "file does not exist", would hide that.
func requireUI(fsys fs.FS) error {
	pages, err := fs.Glob(fsys, "pages/*.html")
	if err != nil || len(pages) == 0 {
		return errors.New("web: the embedded UI (web/api/embed) has no pages; run `pnpm build` in web/ first (or `bash web/scripts/sync-public.sh` for the pages alone; every make target does it)")
	}
	return nil
}

// mustLoad reads an embedded page from pages/ and fills in the footer build id.
func mustLoad(name, buildID string) asset {
	b, err := content.ReadFile(name)
	if err != nil {
		panic(err)
	}
	return newAsset(name, injectBuildID(b, pagePlaceholder, buildID))
}

// errorPage is the generated 404 page: it has a Content-Length (set by serve) but no
// ETag, so an error is never answered with a 304 and never cached as a validator.
func errorPage(b []byte) asset {
	return asset{body: b, ctype: contentType("x.html")}
}

func newAsset(name string, b []byte) asset {
	sum := sha256.Sum256(b)
	return asset{body: b, ctype: contentType(name), etag: `"` + hex.EncodeToString(sum[:16]) + `"`}
}

func contentType(name string) string {
	switch strings.ToLower(path.Ext(name)) {
	case ".html":
		return "text/html; charset=utf-8"
	case ".css":
		return "text/css; charset=utf-8"
	case ".js", ".mjs":
		return "text/javascript; charset=utf-8"
	case ".svg":
		return "image/svg+xml"
	case ".woff2": // not in Go's built-in table; system mime files differ between machines
		return "font/woff2"
	case ".woff":
		return "font/woff"
	}
	if t := mime.TypeByExtension(path.Ext(name)); t != "" {
		return t
	}
	return "application/octet-stream"
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	p := r.URL.Path
	switch {
	case len(p) > 2 && strings.HasSuffix(p, "/") && h.isPage(strings.TrimSuffix(p, "/")):
		// "/terms/" -> "/terms". The Location is a path, never an absolute URL: behind the
		// TLS-terminating proxy the request scheme is plain http, and a relative redirect lets
		// the browser keep the scheme and host it actually used.
		target := strings.TrimSuffix(p, "/")
		if r.URL.RawQuery != "" {
			target += "?" + r.URL.RawQuery
		}
		w.Header().Set("Location", target)
		w.Header().Set("Content-Length", "0")
		w.WriteHeader(http.StatusMovedPermanently)
	default:
		if a, ok := h.pages[p]; ok {
			serve(w, r, http.StatusOK, a, cacheRevalidate)
		} else if a, ok := h.static[p]; ok {
			serve(w, r, http.StatusOK, a, cacheRevalidate)
		} else {
			h.notFoundPage(w, r)
		}
	}
}

// isPage reports whether p is a public page route other than "/".
func (h *handler) isPage(p string) bool {
	_, ok := h.pages[p]
	return ok && p != "/"
}

func (h *handler) notFoundPage(w http.ResponseWriter, r *http.Request) {
	serve(w, r, http.StatusNotFound, h.notFound, cacheRevalidate)
}

// serve writes a fully buffered response with an explicit Content-Length (the
// panel's HTTP/1.0 proxy corrupts chunked bodies) and honours If-None-Match.
func serve(w http.ResponseWriter, r *http.Request, status int, a asset, cacheControl string) {
	hd := w.Header()
	hd.Set("Content-Type", a.ctype)
	hd.Set("Cache-Control", cacheControl)
	hd.Set("X-Content-Type-Options", "nosniff")
	if a.etag != "" {
		hd.Set("ETag", a.etag)
		if status == http.StatusOK && etagMatches(r.Header.Get("If-None-Match"), a.etag) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
	}
	hd.Set("Content-Length", strconv.Itoa(len(a.body)))
	w.WriteHeader(status)
	if r.Method != http.MethodHead {
		_, _ = w.Write(a.body)
	}
}

func etagMatches(header, etag string) bool {
	for _, c := range strings.Split(header, ",") {
		c = strings.TrimPrefix(strings.TrimSpace(c), "W/")
		if c == etag || c == "*" {
			return true
		}
	}
	return false
}
