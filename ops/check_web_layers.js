// Run the web studio's own layer-building code outside a browser and check
// what it produces, against two things that must agree with it:
//   - the server's subtitle parser, so a caption typed in the studio and one
//     imported from an .srt are the same kind of object
//   - the app's SubtitleSegment.fromJson, which non-null-asserts a few keys and
//     throws in the middle of a customer's session if one is missing
const fs = require('fs');

const html = fs.readFileSync(process.argv[2], 'utf8');
const script = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));

// The studio's pure pieces, lifted out. Everything they touch is passed in.
function lift(name) {
  const at = script.indexOf('function ' + name + '(');
  if (at < 0) throw new Error('not found in the deployed page: ' + name);
  let depth = 0, i = script.indexOf('{', at);
  const start = at;
  for (; i < script.length; i++) {
    if (script[i] === '{') depth++;
    else if (script[i] === '}') { depth--; if (depth === 0) break; }
  }
  return script.slice(start, i + 1);
}

const sandbox = {};
// CREATOR is module state in the page; give the lifted functions their own.
eval(lift('capLayer'));
eval(lift('crFitCaptions'));
const CREATOR = { base: null, mark: null, caps: [], duration: 0, shortEdge: 0 };
// crOverlays reads two inputs off the DOM; stand them in.
const fields = { chandle: '', ccta: '' };
global.document = { getElementById: id => (id in fields ? { value: fields[id] } : null) };
eval(lift('crOverlays').replace(/\bCREATOR\b/g, 'CREATOR'));

let failures = 0;
function check(what, ok, detail) {
  console.log((ok ? '  ok   ' : '  FAIL ') + what + (detail ? '  ' + detail : ''));
  if (!ok) failures++;
}

// ── 1. the shape the app insists on ──────────────────────────────────────
// SubtitleSegment.fromJson non-null-asserts these; a missing one is an
// exception in the middle of a customer's editing session.
const REQUIRED = ['t', 's', 'e', 'c', 'fs', 'dx', 'dy'];
console.log('\n1. a caption layer carries what the app reads');
const cap = capLayer({ t: 'hello', s: 1, e: 2 });
for (const k of REQUIRED) check('has ' + k, k in cap && cap[k] !== undefined);
check('kind defaults to text', cap.k === 'text');

// ── 2. the studio and the server agree ───────────────────────────────────
console.log('\n2. the studio and the server make the same kind of caption');
const serverDefaults = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const webDefaults = capLayer({});
const differing = [];
for (const [k, v] of Object.entries(serverDefaults)) {
  if (k === 't' || k === 's' || k === 'e' || k === 'z') continue; // per-caption
  if (JSON.stringify(webDefaults[k]) !== JSON.stringify(v)) {
    differing.push(`${k}: web=${JSON.stringify(webDefaults[k])} server=${JSON.stringify(v)}`);
  }
}
check('every default matches', differing.length === 0, differing.join(' | '));

// ── 3. captions are cut to the footage ───────────────────────────────────
console.log('\n3. captions are cut to the clip');
CREATOR.caps = [
  capLayer({ t: 'inside', s: 1, e: 3 }),
  capLayer({ t: 'overruns', s: 7, e: 20 }),
  capLayer({ t: 'past the end', s: 30, e: 32 }),
];
CREATOR.duration = 10;
const dropped = crFitCaptions();
check('one dropped', dropped === 1, 'dropped=' + dropped);
check('two kept', CREATOR.caps.length === 2);
check('the overrunning one is trimmed to the end', CREATOR.caps[1].e === 10, 'e=' + CREATOR.caps[1].e);
check('the one inside is untouched', CREATOR.caps[0].e === 3);

CREATOR.duration = 0; // no clip yet: nothing to measure against, nothing dropped
const before = CREATOR.caps.length;
check('with no clip yet, nothing is dropped', crFitCaptions() === 0 && CREATOR.caps.length === before);

// ── 4. the handle and the CTA ────────────────────────────────────────────
console.log('\n4. the handle and the call to action');
CREATOR.duration = 12;
CREATOR.shortEdge = 1080;
CREATOR.mark = { key: 'marks/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/m.png' };
fields.chandle = '  @yourpage  ';
fields.ccta = 'Follow for more';
const ov = crOverlays();
const byKind = Object.fromEntries(ov.subs.map(s => [s.k, s]));
check('the handle is there, trimmed', byKind.handle && byKind.handle.t === '@yourpage');
check('the handle runs the whole clip', byKind.handle.s === 0 && byKind.handle.e === 12);
check('the handle sits low', byKind.handle.dy === 0.93);
check('the CTA is there', !!byKind.cta);
check('the CTA is the last couple of seconds', byKind.cta.s === 9.5 && byKind.cta.e === 12);
check('z is unique per layer', new Set(ov.subs.map(s => s.z)).size === ov.subs.length);
check('the frame it was written against travels', ov.authoredShort === 1080);
check('the mark travels as a key', ov.logoKey.startsWith('marks/'));
check('no URL is invented for the mark', !('logoUrl' in ov));

console.log('\n5. nothing to ship is nothing to send');
CREATOR.caps = []; CREATOR.mark = null; fields.chandle = ''; fields.ccta = '';
check('empty studio sends no overlays', crOverlays() === null);

console.log(failures ? `\n${failures} FAILED` : '\nall good');
process.exit(failures ? 1 : 0);
