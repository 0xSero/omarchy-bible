const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");
const context = { console, JSON, Math, String, parseInt, Date };
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), context, { filename: "Model.js" });

const kjv = JSON.parse(fs.readFileSync(path.join(root, "data", "kjv.json"), "utf8"));
const options = { red: "#c95656", accent: "#e5c07b", redLetters: true };

function chapter(book, number) {
  return context.chapterItems(kjv, book, number, options);
}

test("reference parser accepts the shapes the jump field promises", () => {
  const cases = [
    ["jn 3:16", 42, 3, 16],
    ["Rom 8", 44, 8, 0],
    ["1co13", 45, 13, 0],
    ["revalation 21", 65, 21, 0],
    ["ps 23", 18, 23, 0],
    ["song of solomon 2", 21, 2, 0],
    ["1 john 4:8", 61, 4, 8],
    ["3:16", 42, 3, 16],
  ];
  for (const [input, book, number, verse] of cases) {
    const parsed = context.parseReference(input, 42);
    assert.ok(parsed, input);
    assert.equal(parsed.book, book, input);
    assert.equal(parsed.chapter, number, input);
    assert.equal(parsed.verse, verse, input);
  }
  assert.equal(context.parseReference("nonsense", 42), null);
});

test("John 3:16 is typeset with words of Christ in the chosen red", () => {
  const items = chapter(42, 3);
  const verse = items.find((item) => item.type === "verse" && item.number === 16);
  assert.match(verse.html, /^<font color="#c95656">/);
  assert.match(verse.html, /For God so loved the world/);
});

test("span offsets survive curly quotes (byte offsets were converted)", () => {
  const genesis = chapter(0, 4);
  const verse = genesis.find((item) => item.type === "verse" && item.number === 9);
  assert.match(verse.html, /<i>is<\/i> Abel/);
  assert.match(verse.html, /<i>Am<\/i> I my brother’s keeper/);
});

test("turning red letters off removes the font wrapper", () => {
  const items = context.chapterItems(kjv, 42, 3, { ...options, redLetters: false });
  const verse = items.find((item) => item.type === "verse" && item.number === 16);
  assert.doesNotMatch(verse.html, /<font/);
});

test("chapter data keeps poetry marks and headings out of the verse body", () => {
  const psalm = chapter(18, 23);
  assert.equal(psalm.filter((item) => item.type === "verse").length, 6);
  assert.equal(psalm[0].html, "The <span style=\"font-variant:small-caps\">LORD</span> <i>is</i> my shepherd; I shall not want.");
});

test("search requires every token and supports quoted phrases", () => {
  const index = context.buildSearchIndex(kjv);
  const phrase = Array.from(context.search(index, '"still waters"', options, 10), (hit) => hit.reference);
  assert.deepEqual(phrase, ["Psalm 23:2"]);
  const every = context.search(index, "God so loved", options, 5);
  assert.ok(every.some((hit) => hit.reference === "John 3:16"));
  assert.equal(context.search(index, "God so loved -world", options, 50).some((hit) => hit.reference === "John 3:16"), false);
});

test("activity grid ends today, stays private and counts chapters per day", () => {
  const now = new Date(2026, 9, 20); // Tuesday
  const yesterday = new Date(2026, 9, 19);
  const activity = {
    days: {
      [context.dateKey(now)]: { c: 3, k: ["42:3", "42:4", "42:5"] },
      [context.dateKey(yesterday)]: { c: 1, k: ["19:23"] }
    },
    seen: ["42:3", "42:4", "42:5", "19:23"],
    books: [42, 18]
  };
  const view = context.activityView(activity, now);
  assert.equal(view.cells.length, 135); // 19 full weeks + Monday + Tuesday
  assert.equal(view.cells[view.cells.length - 1], 4);
  assert.equal(view.labels[view.labels.length - 1], "Tue Oct 20  3 chapters");
  assert.equal(view.streak, 2);
  assert.equal(view.week, 4);
  assert.equal(view.chapters, 4);
  assert.equal(view.books, 2);
  assert.equal(view.activeDays, 2);
  assert.equal(view.since, "since Oct 19");
  assert.equal(view.empty, false);
});

test("an empty activity file produces a blank grid, not a broken one", () => {
  const view = context.activityView({ days: {}, seen: [], books: [] }, new Date(2026, 9, 20));
  assert.ok(view.cells.length > 0);
  assert.equal(view.chapters, 0);
  assert.equal(view.streak, 0);
  assert.equal(view.empty, true);
  assert.ok(view.cells.every((level) => level === 0));
});
