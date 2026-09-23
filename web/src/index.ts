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
    // Behind DreamHost's reverse proxy, `c.req.url` carries the *internal* scheme (plain http --
    // the proxy terminates TLS), not what the visitor's browser actually used, so building an
    // absolute redirect from it silently downgrades a real https:// visit to http://. The proxy
    // does NOT send `X-Forwarded-Proto` (verified in production; an earlier fix relied on it and
    // never worked), so redirect to a *relative* Location instead -- the browser resolves it
    // against the URL it actually requested, keeping its scheme and host with nothing to guess.
    return c.redirect(`${url.pathname.slice(0, -1)}${url.search}`, 301);
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
      <h1>Tasks and events, one agenda.<span class="sub">To Do List &amp; Calendar for iOS</span></h1>
    </header>
    <main>
      <p>
        <strong>Stark</strong> is a minimal to-do list and calendar for iPhone. Reminders and events
        share one scrolling agenda, with a week, month and year calendar above it — no accounts,
        no cloud lock-in, no subscriptions.
      </p>
      <p>
        Repeat anything daily, weekly, monthly or yearly, or with a custom rule. Search your whole
        history. Everything stays on your device — nothing is sent anywhere.
      </p>
      <a class="badge" href="https://apps.apple.com/app/id6772774783">↓ DOWNLOAD ON THE APP STORE</a>
    </main>
    <div class="screenshots">
      <img src="/public/screenshots/01-agenda.png" alt="Month calendar with today's reminders and events in one agenda">
      <img src="/public/screenshots/02-week.png" alt="Week view with the agenda for today and tomorrow">
      <img src="/public/screenshots/03-year.png" alt="Year view with busy days highlighted">
      <img src="/public/screenshots/04-search.png" alt="Search results for a person tag">
      <img src="/public/screenshots/05-event.png" alt="Editing an event">
      <img src="/public/screenshots/06-add.png" alt="Adding a new event">
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
      <p>Stark stores your data locally on your device. See the <a href="/privacy" style="color:#E8461A;text-decoration:none;">Privacy Policy</a> for details — Stark itself collects nothing.</p>

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
      <p class="updated">LAST UPDATED: SEPTEMBER 2026</p>
    </header>
    <main>
      <h2>THE SHORT VERSION</h2>
      <p><strong>Stark collects no data about you.</strong> Your reminders and events stay on your device. Nothing is sent to us or any third party.</p>

      <h2>DATA STORAGE</h2>
      <p>All reminders and events are stored in files inside Stark's private storage on your device. Stark does not use iCloud and does not sync between devices.</p>
      <p>If you back up your device with iCloud Backup or to a computer, Apple's backup includes Stark's data along with your other apps. That backup is handled entirely by Apple using your Apple ID. We have no access to it and never receive your data.</p>

      <h2>DATA COLLECTION</h2>
      <p>Stark does <strong>not</strong> collect, transmit, or store any of the following:</p>
      <p>— Personal information or identifiers<br>
      — Usage data or analytics<br>
      — Crash reports or diagnostics<br>
      — Location data<br>
      — Reminder or event content or metadata</p>
      <p>Stark does not ask for access to your contacts, calendars, photos, location, or notifications.</p>

      <h2>LINKS</h2>
      <p>If you tap a link in Stark, such as an event's URL or a link in Settings, it opens in your browser. That site's own privacy policy applies to your visit.</p>

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
      On your device only, in Stark's private storage, as standard iCalendar (<strong>.ics</strong>) files. Nothing is uploaded and there is no account.</p>

      <p><strong>Does Stark sync between my devices?</strong><br>
      No. Each device keeps its own data. Stark's data is included in your normal device backups (iCloud Backup or a computer backup), so restoring a device from a backup restores it too.</p>

      <p><strong>How do I add a recurring reminder or event?</strong><br>
      Tap + to add an item, then use the Repeat row to choose daily, weekly, monthly or yearly, or a custom rule such as every two weeks or the first Tuesday of the month. Repeat End stops the series after a date or a number of times. Completing a repeating reminder completes only that occurrence; the series continues.</p>

      <p><strong>What happens to a reminder I miss?</strong><br>
      An overdue reminder moves to today's section with its missed date shown, until you complete or skip it. Missed daily repeats are not carried forward, so they don't nag you every day.</p>

      <p><strong>Can I record whether I attended an event?</strong><br>
      Yes. Open the event and choose Attended or Didn't Attend. The event stays on your agenda, marked and dimmed, and you can clear the mark at any time.</p>

      <p><strong>Can I search old items?</strong><br>
      Yes. Search looks through the titles, notes and locations of everything you have ever saved, not just what is near today's date.</p>

      <p><strong>Can I tag people, projects, or labels in a task?</strong><br>
      Yes — just type the tag anywhere in the title or notes. <strong>+project</strong> and <strong>@context</strong> are todo.txt's own standard tags; <strong>%label</strong> and <strong>~person</strong> are free-form ones Stark also understands, for whatever categories or people you want to track (e.g. "Call mom ~mom %family"). As you type a tag, Stark suggests matching ones you've already used elsewhere, so you don't have to remember your own spelling.</p>

      <p><strong>Does Stark work offline?</strong><br>
      Yes. Stark never needs a connection: everything is read from and written to your device.</p>
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
