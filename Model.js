// Pure helpers for the Bible panel: canon table, reference parsing, typeset
// verse HTML, search and snippets. No QML objects here, so the panel can call
// these without binding loops.
//
// Translation JSON (data/<id>.json) is the bible-rs .bbl layout flattened:
//   chapters[chapterIndex] = [[number, numberEnd, text, marks, spans], ...]
//   mark = [offset, kind, level, payload]
//   span = [start, end, style]
// Offsets are QML string indices (the build script converts .bbl byte offsets).

var BOOKS = [
  { name: "Genesis", abbr: "Gen", chapters: 50, aliases: ["gen", "ge", "gn"] },
  { name: "Exodus", abbr: "Exod", chapters: 40, aliases: ["ex", "exo", "exod", "exd"] },
  { name: "Leviticus", abbr: "Lev", chapters: 27, aliases: ["lev", "le", "lv"] },
  { name: "Numbers", abbr: "Num", chapters: 36, aliases: ["num", "nu", "nm", "nb"] },
  { name: "Deuteronomy", abbr: "Deut", chapters: 34, aliases: ["deut", "deu", "de", "dt"] },
  { name: "Joshua", abbr: "Josh", chapters: 24, aliases: ["josh", "jos", "jsh"] },
  { name: "Judges", abbr: "Judg", chapters: 21, aliases: ["judg", "jdg", "jg", "jdgs"] },
  { name: "Ruth", abbr: "Ruth", chapters: 4, aliases: ["ruth", "rth", "ru", "rut"] },
  { name: "1 Samuel", abbr: "1 Sam", chapters: 31, aliases: ["1sam", "1sa", "1sm", "1s", "1kgdms"] },
  { name: "2 Samuel", abbr: "2 Sam", chapters: 24, aliases: ["2sam", "2sa", "2sm", "2s"] },
  { name: "1 Kings", abbr: "1 Kgs", chapters: 22, aliases: ["1kgs", "1ki", "1kin", "1k", "1kg"] },
  { name: "2 Kings", abbr: "2 Kgs", chapters: 25, aliases: ["2kgs", "2ki", "2kin", "2k", "2kg"] },
  { name: "1 Chronicles", abbr: "1 Chr", chapters: 29, aliases: ["1chr", "1ch", "1chron", "1chro"] },
  { name: "2 Chronicles", abbr: "2 Chr", chapters: 36, aliases: ["2chr", "2ch", "2chron", "2chro"] },
  { name: "Ezra", abbr: "Ezra", chapters: 10, aliases: ["ezra", "ezr", "ez"] },
  { name: "Nehemiah", abbr: "Neh", chapters: 13, aliases: ["neh", "ne"] },
  { name: "Esther", abbr: "Esth", chapters: 10, aliases: ["esth", "est", "es"] },
  { name: "Job", abbr: "Job", chapters: 42, aliases: ["job", "jb"] },
  { name: "Psalms", abbr: "Ps", chapters: 150, aliases: ["ps", "psa", "psalm", "pss", "psm", "pslm"] },
  { name: "Proverbs", abbr: "Prov", chapters: 31, aliases: ["prov", "pro", "prv", "pr"] },
  { name: "Ecclesiastes", abbr: "Eccl", chapters: 12, aliases: ["eccl", "ecc", "ec", "eccles", "qoh", "qoheleth"] },
  { name: "Song of Solomon", abbr: "Song", chapters: 8, aliases: ["song", "sng", "sos", "so", "songofsongs", "canticles", "cant"] },
  { name: "Isaiah", abbr: "Isa", chapters: 66, aliases: ["isa", "is"] },
  { name: "Jeremiah", abbr: "Jer", chapters: 52, aliases: ["jer", "je", "jr"] },
  { name: "Lamentations", abbr: "Lam", chapters: 5, aliases: ["lam", "la"] },
  { name: "Ezekiel", abbr: "Ezek", chapters: 48, aliases: ["ezek", "eze", "ezk"] },
  { name: "Daniel", abbr: "Dan", chapters: 12, aliases: ["dan", "da", "dn"] },
  { name: "Hosea", abbr: "Hos", chapters: 14, aliases: ["hos", "ho"] },
  { name: "Joel", abbr: "Joel", chapters: 3, aliases: ["joel", "jl", "jol"] },
  { name: "Amos", abbr: "Amos", chapters: 9, aliases: ["amos", "am", "amo"] },
  { name: "Obadiah", abbr: "Obad", chapters: 1, aliases: ["obad", "ob", "oba"] },
  { name: "Jonah", abbr: "Jonah", chapters: 4, aliases: ["jonah", "jnh", "jon"] },
  { name: "Micah", abbr: "Mic", chapters: 7, aliases: ["mic", "mc"] },
  { name: "Nahum", abbr: "Nah", chapters: 3, aliases: ["nah", "na", "nam"] },
  { name: "Habakkuk", abbr: "Hab", chapters: 3, aliases: ["hab", "hb"] },
  { name: "Zephaniah", abbr: "Zeph", chapters: 3, aliases: ["zeph", "zep", "zp"] },
  { name: "Haggai", abbr: "Hag", chapters: 2, aliases: ["hag", "hg"] },
  { name: "Zechariah", abbr: "Zech", chapters: 14, aliases: ["zech", "zec", "zc"] },
  { name: "Malachi", abbr: "Mal", chapters: 4, aliases: ["mal", "ml"] },
  { name: "Matthew", abbr: "Matt", chapters: 28, aliases: ["matt", "mat", "mt"] },
  { name: "Mark", abbr: "Mark", chapters: 16, aliases: ["mark", "mrk", "mk", "mr", "mar"] },
  { name: "Luke", abbr: "Luke", chapters: 24, aliases: ["luke", "luk", "lk", "lu"] },
  { name: "John", abbr: "John", chapters: 21, aliases: ["john", "jhn", "jn", "joh", "jo"] },
  { name: "Acts", abbr: "Acts", chapters: 28, aliases: ["acts", "act", "ac"] },
  { name: "Romans", abbr: "Rom", chapters: 16, aliases: ["rom", "ro", "rm"] },
  { name: "1 Corinthians", abbr: "1 Cor", chapters: 16, aliases: ["1cor", "1co", "1corinthians"] },
  { name: "2 Corinthians", abbr: "2 Cor", chapters: 13, aliases: ["2cor", "2co", "2corinthians"] },
  { name: "Galatians", abbr: "Gal", chapters: 6, aliases: ["gal", "ga"] },
  { name: "Ephesians", abbr: "Eph", chapters: 6, aliases: ["eph", "ephes"] },
  { name: "Philippians", abbr: "Phil", chapters: 4, aliases: ["phil", "php", "pp", "philip"] },
  { name: "Colossians", abbr: "Col", chapters: 4, aliases: ["col", "co"] },
  { name: "1 Thessalonians", abbr: "1 Thess", chapters: 5, aliases: ["1thess", "1th", "1thes", "1ts"] },
  { name: "2 Thessalonians", abbr: "2 Thess", chapters: 3, aliases: ["2thess", "2th", "2thes", "2ts"] },
  { name: "1 Timothy", abbr: "1 Tim", chapters: 6, aliases: ["1tim", "1ti", "1tm"] },
  { name: "2 Timothy", abbr: "2 Tim", chapters: 4, aliases: ["2tim", "2ti", "2tm"] },
  { name: "Titus", abbr: "Titus", chapters: 3, aliases: ["titus", "tit", "ti"] },
  { name: "Philemon", abbr: "Phlm", chapters: 1, aliases: ["phlm", "phm", "philem", "pm"] },
  { name: "Hebrews", abbr: "Heb", chapters: 13, aliases: ["heb", "he"] },
  { name: "James", abbr: "Jas", chapters: 5, aliases: ["jas", "jm", "jam", "james"] },
  { name: "1 Peter", abbr: "1 Pet", chapters: 5, aliases: ["1pet", "1pe", "1pt", "1p"] },
  { name: "2 Peter", abbr: "2 Pet", chapters: 3, aliases: ["2pet", "2pe", "2pt", "2p"] },
  { name: "1 John", abbr: "1 John", chapters: 5, aliases: ["1john", "1jn", "1jhn", "1j", "1jo"] },
  { name: "2 John", abbr: "2 John", chapters: 1, aliases: ["2john", "2jn", "2jhn", "2j", "2jo"] },
  { name: "3 John", abbr: "3 John", chapters: 1, aliases: ["3john", "3jn", "3jhn", "3j", "3jo"] },
  { name: "Jude", abbr: "Jude", chapters: 1, aliases: ["jude", "jud", "jd"] },
  { name: "Revelation", abbr: "Rev", chapters: 22, aliases: ["rev", "re", "rv", "revelations", "apocalypse", "apoc"] }
];

var TRANSLATIONS = [
  { id: "kjv", abbrev: "KJV", name: "King James Version" },
  { id: "web", abbrev: "WEB", name: "World English Bible" },
  { id: "bsb", abbrev: "BSB", name: "Berean Standard Bible" },
  { id: "asv", abbrev: "ASV", name: "American Standard Version" },
  { id: "ylt", abbrev: "YLT", name: "Young's Literal Translation" },
  { id: "dby", abbrev: "DBY", name: "Darby Translation" },
  { id: "wbs", abbrev: "WBS", name: "Webster Bible" }
];

var OFFSETS = (function() {
  var out = [], sum = 0;
  for (var i = 0; i < BOOKS.length; i++) { out.push(sum); sum += BOOKS[i].chapters; }
  out.push(sum);
  return out;
})();

function bookName(book) { return BOOKS[book] ? BOOKS[book].name : ""; }
function bookAbbr(book) { return BOOKS[book] ? BOOKS[book].abbr : ""; }
function chapterLabel(book, chapter) {
  var name = bookName(book);
  if (book === 18) name = "Psalm";
  return name + " " + chapter;
}
function referenceLabel(book, chapter, verse, end) {
  var label = chapterLabel(book, chapter);
  if (verse !== undefined && verse !== null && verse > 0)
    label += ":" + verse + (end && end !== verse ? "-" + end : "");
  return label;
}
function verseKey(book, chapter, verse) { return book + ":" + chapter + ":" + verse; }
function chapterIndex(book, chapter) { return OFFSETS[book] + chapter - 1; }
function chapterVerses(translation, book, chapter) {
  if (!translation) return [];
  var idx = chapterIndex(book, chapter);
  return translation.chapters[idx] || [];
}
function translationAbbrev(id) {
  for (var i = 0; i < TRANSLATIONS.length; i++) if (TRANSLATIONS[i].id === id) return TRANSLATIONS[i].abbrev;
  return id.toUpperCase();
}

function esc(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function spaces(count) {
  var out = "";
  for (var i = 0; i < count; i++) out += "&nbsp;";
  return out;
}

// A span may be red letters (0), added/italic (1, 3, 4), divine name (2),
// bold (5) or small caps (6). Tags close in reverse order.
function styleOpen(active, opts) {
  var open = "";
  // <font> is the one color form Qt's rich-text engine always honors;
  // CSS color on a span is not reliable across Qt versions.
  if (active[0] && opts.redLetters) open += '<font color="' + opts.red + '">';
  if (active[5]) open += "<b>";
  if (active[1] || active[3] || active[4]) open += "<i>";
  if (active[2] || active[6]) open += '<span style="font-variant:small-caps">';
  return open;
}
function styleClose(active, opts) {
  var close = "";
  if (active[2] || active[6]) close += "</span>";
  if (active[1] || active[3] || active[4]) close += "</i>";
  if (active[5]) close += "</b>";
  if (active[0] && opts.redLetters) close += "</font>";
  return close;
}

function markBreak(kind, level) {
  // Paragraph (0), flush paragraph (1), poetry (2), right poetry (3),
  // centered (4), list (5), stanza blank (6). Headings are chapter items.
  if (kind === 2 || kind === 3 || kind === 5)
    return "<br/>" + spaces(Math.max(0, level) * 3);
  if (kind === 4)
    return "<br/>" + spaces(8);
  if (kind === 6)
    return "<br/><br/>";
  if (kind === 0 || kind === 1)
    return "<br/><br/>";
  return "";
}

function verseHtml(verse, opts) {
  var text = String(verse[2] || "");
  var marks = verse[3] || [];
  var spans = verse[4] || [];
  var events = {};
  function event(pos) {
    if (!events[pos]) events[pos] = { marks: [], add: [], del: [] };
    return events[pos];
  }
  for (var m = 0; m < marks.length; m++) {
    var mark = marks[m];
    if (mark[1] >= 7) continue; // heading, psalm title, speaker: chapter items
    if (mark[0] === 0) continue;
    event(mark[0]).marks.push(mark);
  }
  for (var s = 0; s < spans.length; s++) {
    var span = spans[s];
    event(span[0]).add.push(span);
    event(span[1]).del.push(span);
  }

  var positions = [];
  for (var key in events) positions.push(parseInt(key, 10));
  positions.sort(function(a, b) { return a - b; });

  var active = [0, 0, 0, 0, 0, 0, 0];
  var html = "";
  var at = 0;
  for (var p = 0; p < positions.length; p++) {
    var pos = positions[p];
    if (pos > text.length) pos = text.length;
    if (pos < at) continue;
    if (pos > at) {
      html += styleOpen(active, opts);
      html += esc(text.slice(at, pos));
      html += styleClose(active, opts);
    }
    var ev = events[positions[p]] || events[pos];
    if (ev) {
      for (var d = 0; d < ev.del.length; d++) active[ev.del[d][2]] = Math.max(0, active[ev.del[d][2]] - 1);
      for (var mk = 0; mk < ev.marks.length; mk++) html += markBreak(ev.marks[mk][1], ev.marks[mk][2]);
      for (var a = 0; a < ev.add.length; a++) active[ev.add[a][2]]++;
    }
    at = pos;
  }
  if (at < text.length) {
    html += styleOpen(active, opts);
    html += esc(text.slice(at));
    html += styleClose(active, opts);
  }
  return html || "&nbsp;";
}

function plainText(verse) {
  var text = String(verse[2] || "");
  var marks = verse[3] || [];
  var out = "", at = 0;
  var ordered = marks.slice().sort(function(a, b) { return a[0] - b[0]; });
  for (var i = 0; i < ordered.length; i++) {
    var m = ordered[i];
    if (m[0] < 0 || m[0] > text.length) continue;
    if (m[0] > at) out += text.slice(at, m[0]);
    if (m[0] > 0 || out.length > 0) out += " ";
    at = m[0];
  }
  out += text.slice(at);
  return out.replace(/\s+/g, " ").trim();
}

function chapterItems(translation, book, chapter, opts) {
  var verses = chapterVerses(translation, book, chapter);
  var items = [];
  var seen = {};
  for (var i = 0; i < verses.length; i++) {
    var verse = verses[i];
    var marks = verse[3] || [];
    for (var m = 0; m < marks.length; m++) {
      var mark = marks[m];
      if (mark[1] !== 7 && mark[1] !== 8 && mark[1] !== 9) continue;
      var payload = String(mark[3] || "").trim();
      if (!payload) continue;
      var key = mark[1] + "|" + payload;
      if (seen[key]) continue;
      seen[key] = true;
      items.push({ type: "heading", text: payload, level: mark[1] === 7 ? (mark[2] || 1) : (mark[1] === 8 ? 3 : 2) });
    }
    items.push({
      type: "verse",
      index: i,
      number: verse[0],
      end: verse[1],
      html: verseHtml(verse, opts)
    });
  }
  return items;
}

function normalizeQuery(text) {
  var tokens = [], exclude = [];
  var re = /"([^"]+)"|(\S+)/g, match;
  while ((match = re.exec(text)) !== null) {
    var token = (match[1] || match[2] || "").trim().toLowerCase();
    if (!token) continue;
    if (token.charAt(0) === "-" && token.length > 1) exclude.push(token.slice(1));
    else tokens.push(token);
  }
  return { tokens: tokens, exclude: exclude };
}

function buildSearchIndex(translation) {
  var index = [];
  var offset = 0;
  for (var b = 0; b < BOOKS.length; b++) {
    for (var c = 1; c <= BOOKS[b].chapters; c++) {
      var verses = translation.chapters[offset++] || [];
      for (var i = 0; i < verses.length; i++) {
        var text = plainText(verses[i]);
        index.push({ book: b, chapter: c, index: i, number: verses[i][0], end: verses[i][1], text: text, low: text.toLowerCase() });
      }
    }
  }
  return index;
}

function search(index, query, opts, limit) {
  var parsed = normalizeQuery(query);
  var out = [];
  if (!parsed.tokens.length) return out;
  var cap = limit || 80;
  for (var i = 0; i < index.length && out.length < cap; i++) {
    var row = index[i], ok = true;
    for (var e = 0; e < parsed.exclude.length; e++) {
      if (row.low.indexOf(parsed.exclude[e]) >= 0) { ok = false; break; }
    }
    if (!ok) continue;
    for (var t = 0; t < parsed.tokens.length; t++) {
      if (row.low.indexOf(parsed.tokens[t]) < 0) { ok = false; break; }
    }
    if (!ok) continue;
    out.push({
      book: row.book, chapter: row.chapter, index: row.index, number: row.number, end: row.end,
      reference: referenceLabel(row.book, row.chapter, row.number, row.end),
      snippet: snippet(row.text, parsed.tokens[0], opts),
      text: row.text
    });
  }
  return out;
}

function snippet(text, token, opts) {
  var low = text.toLowerCase();
  var at = low.indexOf(token);
  if (at < 0) at = 0;
  var start = Math.max(0, at - 52);
  var end = Math.min(text.length, at + token.length + 72);
  // Do not open or close the snippet in the middle of a word.
  if (start > 0) { var space = text.indexOf(" ", start); if (space > 0 && space < at) start = space + 1; }
  if (end < text.length) { var lastSpace = text.lastIndexOf(" ", end); if (lastSpace > at + token.length) end = lastSpace; }
  var lead = start > 0 ? "… " : "";
  var tail = end < text.length ? " …" : "";
  var body = text.slice(start, end);
  var hit = body.toLowerCase().indexOf(token);
  if (hit < 0) return esc(lead + body + tail);
  return esc(lead + body.slice(0, hit)) +
    '<font color="' + opts.accent + '"><b>' + esc(body.slice(hit, hit + token.length)) + "</b></font>" +
    esc(body.slice(hit + token.length) + tail);
}

function normalizeBook(token) {
  return String(token).toLowerCase().replace(/[.\s]/g, "");
}

function editDistance(a, b) {
  if (a === b) return 0;
  var prev = [], cur = [], i, j;
  for (j = 0; j <= b.length; j++) prev[j] = j;
  for (i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a.charAt(i - 1) === b.charAt(j - 1) ? 0 : 1));
    }
    for (j = 0; j <= b.length; j++) prev[j] = cur[j];
  }
  return prev[b.length];
}

function findBook(token) {
  var normalized = normalizeBook(token);
  if (!normalized) return -1;
  var best = -1, bestDistance = 99;
  for (var i = 0; i < BOOKS.length; i++) {
    var names = [BOOKS[i].name, BOOKS[i].abbr].concat(BOOKS[i].aliases || []);
    for (var n = 0; n < names.length; n++) {
      var candidate = normalizeBook(names[n]);
      if (candidate === normalized) return i;
      var distance = editDistance(normalized, candidate);
      if (distance < bestDistance) { bestDistance = distance; best = i; }
    }
  }
  return bestDistance <= 2 ? best : -1;
}

// "jn 3:16", "1co13", "Rom 8", "revalation 21" and "3:16" (current book) all
// land on the same shape. Returns null when there is no book to name.
function parseReference(input, currentBook) {
  var text = String(input || "").toLowerCase().replace(/\./g, " ").replace(/\s+/g, " ").trim();
  if (!text) return null;

  var verseOnly = text.match(/^(\d+)(?::(\d+)(?:-(\d+))?)?$/);
  if (verseOnly && currentBook !== undefined && currentBook >= 0) {
    var vc = parseInt(verseOnly[1], 10);
    var vv = verseOnly[2] ? parseInt(verseOnly[2], 10) : 0;
    return { book: currentBook, chapter: clamp(vc, 1, BOOKS[currentBook].chapters), verse: vv, end: verseOnly[3] ? parseInt(verseOnly[3], 10) : vv };
  }

  var match = text.match(/^((?:[1-3]\s*)?[a-z][a-z ]*?)\s*(\d+)?(?::\s*(\d+)(?:\s*-\s*(\d+))?)?$/);
  if (!match) return null;
  var book = findBook(match[1]);
  if (book < 0) return null;
  var chapter = match[2] ? parseInt(match[2], 10) : 1;
  chapter = clamp(chapter, 1, BOOKS[book].chapters);
  var verse = match[3] ? parseInt(match[3], 10) : 0;
  var end = match[4] ? parseInt(match[4], 10) : verse;
  return { book: book, chapter: chapter, verse: verse, end: end };
}

function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }
