import { Hono } from 'hono';
import { serveStatic } from 'hono/bun';

const app = new Hono();
const PORT = parseInt(process.env.PORT ?? '3456');

// Hono matches routes exactly, so "/terms/" 404s even though "/terms" is defined -- true of
// every route here (a person typing the URL by habit, or a browser/link adding the slash, hits
// this easily). Redirect any non-root path with a trailing slash to its slash-free form instead
// of 404ing, before any route handler runs.
app.use('*', async (c, next) => {
  const url = new URL(c.req.url);
  if (url.pathname.length > 1 && url.pathname.endsWith('/')) {
    url.pathname = url.pathname.slice(0, -1);
    return c.redirect(url.toString(), 301);
  }
  await next();
});

// ── Shared layout ─────────────────────────────────────────────────────────────

const CSS = `
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #1A1A1A;
    color: #F0F0F0;
    font-family: 'Courier New', Courier, monospace;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
  }
  header {
    padding: 48px 40px 32px;
    border-bottom: 1px solid #333;
  }
  .wordmark { font-size: 13px; letter-spacing: 4px; color: #E8461A; }
  .wordmark a { color: #E8461A; text-decoration: none; }
  h1 { font-size: 28px; font-weight: 400; margin-top: 16px; line-height: 1.3; }
  h1 .sub { color: #888; font-size: 18px; display: block; margin-top: 8px; letter-spacing: 1px; }
  main { padding: 48px 40px; flex: 1; max-width: 640px; }
  h2 { font-size: 11px; letter-spacing: 3px; color: #E8461A; margin-top: 40px; margin-bottom: 12px; }
  h2:first-child { margin-top: 0; }
  p { font-size: 14px; color: #888; line-height: 1.8; margin-bottom: 16px; }
  p strong { color: #F0F0F0; }
  .badge {
    display: inline-block;
    border: 1px solid #333;
    padding: 12px 20px;
    font-size: 13px;
    letter-spacing: 1px;
    color: #888;
    text-decoration: none;
  }
  .badge:hover { border-color: #E8461A; color: #F0F0F0; }
  .contact-block { border: 1px solid #333; padding: 20px 24px; margin-top: 12px; }
  .contact-block a { color: #E8461A; text-decoration: none; }
  .updated { font-size: 11px; color: #555; margin-top: 8px; letter-spacing: 1px; }
  footer {
    padding: 24px 40px;
    border-top: 1px solid #333;
    display: flex;
    gap: 32px;
    font-size: 11px;
    letter-spacing: 1px;
    color: #555;
  }
  footer a { color: #555; text-decoration: none; }
  footer a:hover { color: #E8461A; }
  .screenshots {
    display: flex;
    gap: 16px;
    overflow-x: auto;
    padding: 40px 40px;
    scrollbar-width: none;
    border-top: 1px solid #333;
  }
  .screenshots::-webkit-scrollbar { display: none; }
  .screenshots img {
    height: 480px;
    width: auto;
    flex-shrink: 0;
    display: block;
  }
`;

function layout(title: string, body: string, footerLinks: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <link rel="icon" type="image/x-icon" href="/public/favicon.ico">
  <link rel="icon" type="image/png" sizes="32x32" href="/public/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="/public/favicon-16x16.png">
  <link rel="apple-touch-icon" sizes="180x180" href="/public/apple-touch-icon.png">
  <style>${CSS}</style>
</head>
<body>
  ${body}
  <footer>
    ${footerLinks}
    <span>© ${new Date().getFullYear()} ELADIO CARITOS</span>
  </footer>
</body>
</html>`;
}

app.use('/public/*', serveStatic({ root: './' }));

// ── Routes ────────────────────────────────────────────────────────────────────

app.get('/', (c) => {
  const html = layout(
    'Stark — To Do List & Calendar',
    `<header>
      <div class="wordmark">STARK</div>
      <h1>Plain text tasks.<span class="sub">To Do List &amp; Calendar for iOS</span></h1>
    </header>
    <main>
      <p>
        <strong>Stark</strong> is a minimal task manager and calendar that stores everything
        in a plain text <strong>todo.txt</strong> file — no accounts, no cloud lock-in,
        no subscriptions. Just your tasks, in a format you own.
      </p>
      <p>
        Fully compatible with the <a href="http://todotxt.org/" style="color:#E8461A;text-decoration:none;">todo.txt format</a>
        — an open standard used by apps and tools across every platform.
        Your file works everywhere.
      </p>
      <a class="badge" href="https://apps.apple.com/app/id6772774783">↓ DOWNLOAD ON THE APP STORE</a>

      <h2 style="margin-top:48px;">ALSO AVAILABLE</h2>
      <p>
        Prefer the terminal? A companion <strong>command-line tool</strong> is available for macOS.
        Point it at the same iCloud file and your tasks sync instantly between your iPhone and Mac.
      </p>
      <a class="badge" href="https://github.com/caritos/todo-txt/releases/latest">↓ COMMAND-LINE TOOL ON GITHUB</a>
    </main>
    <div class="screenshots">
      <img src="/public/screenshots/01-calendar.png" alt="Calendar view">
      <img src="/public/screenshots/02-month.png" alt="Month view">
      <img src="/public/screenshots/03-year.png" alt="Year view">
      <img src="/public/screenshots/04-day.png" alt="Day view">
    </div>`,
    `<a href="/privacy">PRIVACY POLICY</a><a href="/terms">TERMS OF SERVICE</a><a href="/faq">FAQ</a><a href="/support">SUPPORT</a>`,
  );
  return c.html(html);
});

app.get('/terms', (c) => {
  const html = layout(
    'Terms of Service — Stark',
    `<header>
      <div class="wordmark"><a href="/">STARK</a></div>
      <h1>Terms of Service</h1>
      <p class="updated">LAST UPDATED: SEPTEMBER 2026</p>
    </header>
    <main>
      <h2>THE SHORT VERSION</h2>
      <p>Stark is provided as-is, for personal task and calendar management. By downloading or using the app, you agree to these terms.</p>

      <h2>ACCEPTANCE OF TERMS</h2>
      <p>By downloading, installing, or using Stark, you agree to be bound by these Terms of Service. If you do not agree, do not use the app.</p>

      <h2>USE OF THE APP</h2>
      <p>Stark is a personal task and calendar manager. You are responsible for the content you create in it and for keeping your device secure.</p>

      <h2>YOUR DATA</h2>
      <p>Stark stores your data locally on your device (and, where offered, in your personal iCloud storage). See the <a href="/privacy" style="color:#E8461A;text-decoration:none;">Privacy Policy</a> for details — Stark itself collects nothing.</p>

      <h2>NO WARRANTY</h2>
      <p>Stark is provided "as is," without warranty of any kind, express or implied. We do not guarantee the app will be error-free or uninterrupted.</p>

      <h2>LIMITATION OF LIABILITY</h2>
      <p>To the maximum extent permitted by law, we are not liable for any damages, including data loss, arising from your use of the app.</p>

      <h2>CHANGES TO THESE TERMS</h2>
      <p>We may update these terms from time to time. Continued use of the app after a change constitutes acceptance of the new terms.</p>

      <h2>CONTACT</h2>
      <p>Questions about these terms? Email <strong>eladio@caritos.com</strong>.</p>
    </main>`,
    `<a href="/">HOME</a><a href="/privacy">PRIVACY POLICY</a><a href="/faq">FAQ</a>`,
  );
  return c.html(html);
});

app.get('/privacy', (c) => {
  const html = layout(
    'Privacy Policy — Stark',
    `<header>
      <div class="wordmark"><a href="/">STARK</a></div>
      <h1>Privacy Policy</h1>
      <p class="updated">LAST UPDATED: JUNE 2026</p>
    </header>
    <main>
      <h2>THE SHORT VERSION</h2>
      <p><strong>Stark collects no data about you.</strong> Your tasks stay on your device and in your personal iCloud storage. Nothing is sent to us or any third party.</p>

      <h2>DATA STORAGE</h2>
      <p>All tasks and calendar data are stored in a plain text <strong>todo.txt</strong> file on your device or in your personal iCloud Drive. You choose the file location in Settings.</p>
      <p>iCloud syncing is handled entirely by Apple using your personal Apple ID. We have no access to your iCloud storage and never receive or transmit your task data.</p>

      <h2>DATA COLLECTION</h2>
      <p>Stark does <strong>not</strong> collect, transmit, or store any of the following:</p>
      <p>— Personal information or identifiers<br>
      — Usage data or analytics<br>
      — Crash reports or diagnostics<br>
      — Location data<br>
      — Task content or metadata</p>

      <h2>THIRD PARTIES</h2>
      <p>Stark contains no third-party analytics, advertising SDKs, or tracking libraries. No data is shared with any third party.</p>

      <h2>CHILDREN</h2>
      <p>Stark does not knowingly collect any information from anyone, including children.</p>

      <h2>CONTACT</h2>
      <p>Questions about this policy? Email <strong>eladio@caritos.com</strong>.</p>
    </main>`,
    `<a href="/">HOME</a><a href="/terms">TERMS OF SERVICE</a><a href="/faq">FAQ</a><a href="/support">SUPPORT</a>`,
  );
  return c.html(html);
});

app.get('/support', (c) => {
  const html = layout(
    'Support — Stark',
    `<header>
      <div class="wordmark"><a href="/">STARK</a></div>
      <h1>Support</h1>
    </header>
    <main>
      <h2>CONTACT</h2>
      <p>For bug reports, feature requests, or general questions:</p>
      <div class="contact-block">
        <a href="mailto:eladio@caritos.com">eladio@caritos.com</a>
      </div>
    </main>`,
    `<a href="/">HOME</a><a href="/faq">FAQ</a><a href="/privacy">PRIVACY POLICY</a><a href="/terms">TERMS OF SERVICE</a>`,
  );
  return c.html(html);
});

app.get('/faq', (c) => {
  const html = layout(
    'FAQ — Stark',
    `<header>
      <div class="wordmark"><a href="/">STARK</a></div>
      <h1>Frequently Asked Questions</h1>
    </header>
    <main>
      <p><strong>Where is my data stored?</strong><br>
      Your tasks are stored in a plain text <strong>todo.txt</strong> file. By default Stark uses iCloud Drive so your tasks sync across your devices. You can point the app to any file location in Settings.</p>

      <p><strong>How do I sync with my Mac or other apps?</strong><br>
      Point both Stark and your other todo.txt app to the same file in iCloud Drive. Any app that reads and writes the todo.txt format will work.</p>

      <p><strong>How do I add a recurring task?</strong><br>
      Add a task and tap it to open the detail view. Use the recurrence picker to set daily, weekly, monthly, or yearly repeats. The task advances to its next occurrence automatically when you mark it done.</p>

      <p><strong>What is todo.txt?</strong><br>
      A simple, open plain text format for task management. One task per line. Human-readable in any text editor. You own your data completely — no proprietary format, no lock-in.</p>

      <p><strong>Can I tag people, projects, or labels in a task?</strong><br>
      Yes — just type the tag anywhere in the title or notes. <strong>+project</strong> and <strong>@context</strong> are todo.txt's own standard tags; <strong>%label</strong> and <strong>~person</strong> are free-form ones Stark also understands, for whatever categories or people you want to track (e.g. "Call mom ~mom %family"). As you type a tag, Stark suggests matching ones you've already used elsewhere, so you don't have to remember your own spelling.</p>

      <p><strong>Does Stark work offline?</strong><br>
      Yes. Stark reads and writes a local file. iCloud syncs when a connection is available, but the app works fully offline.</p>
    </main>`,
    `<a href="/">HOME</a><a href="/support">SUPPORT</a>`,
  );
  return c.html(html);
});

// ── Start ─────────────────────────────────────────────────────────────────────

export default {
  port: PORT,
  fetch: app.fetch,
};

console.log(`stark-web running on port ${PORT}`);
