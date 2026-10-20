pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// A Bible reader in the Omarchy bar. The bar widget is the book mark; the
// panel is the reader. Data comes from bible-rs's public-domain .bbl files,
// flattened to JSON by tools/build_data.py, so the typesetting (paragraphs,
// poetry, red letters, translator italics) is the same text the native app
// draws.
Panel {
  id: root
  moduleName: "sero.bible"
  ipcTarget: "sero.bible"
  property bool alwaysLoad: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color fg: bar && bar.barForeground !== undefined ? bar.barForeground : Commons.Color.foreground
  readonly property color muted: Commons.Color.muted
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color surface: Commons.Color.popups.background
  readonly property string uiFont: bar && bar.fontFamily !== undefined ? bar.fontFamily : Style.font.family
  readonly property string serif: literata.name !== "" ? literata.name : uiFont

  // A monochrome theme has no red or blue to borrow. Words of Christ and
  // search hits keep their meaning instead of turning into another grey.
  function hasChroma(color) {
    return Math.max(color.r, color.g, color.b) - Math.min(color.r, color.g, color.b) > 0.08;
  }
  readonly property color jesusColor: hasChroma(urgent) ? urgent : "#c95656"
  readonly property color matchColor: hasChroma(accent) ? accent : "#e5c07b"

  readonly property int gutter: Style.space(20)
  readonly property int edge: Style.space(8)
  readonly property int footerHeight: editingNote ? Style.space(86) : Style.space(48)

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/bible.json"
  readonly property string activityPath: stateDir + "/bible-activity.json"

  // ---- Canonical position and user data -------------------------------
  property var library: defaultState()
  property bool stateLoaded: false
  property var activity: defaultActivity()
  property bool activityLoaded: false
  property var statsView: ({})
  property int statsHover: -1
  property string translationId: "kjv"
  property var translation: null
  property string loadingId: ""
  property bool loading: false
  property string loadError: ""
  property int book: 42
  property int chapter: 3
  property int selectedVerse: 0
  property string mode: "read"
  property string query: ""
  property var results: []
  property int resultIndex: 0
  property var searchIndex: null
  property string searchIndexId: ""
  property bool editingNote: false
  property string notice: ""
  property int pickerBook: 42
  property var cache: ({})
  property var cacheOrder: []
  property var chapterItems: []
  property var jumpRef: null
  property string jumpPreview: ""

  function defaultState() {
    return {
      version: 1,
      translation: "kjv",
      last: { book: 42, chapter: 3, verse: 0 },
      highlights: {},
      bookmarks: {},
      notes: {},
      redLetters: false,
      fontSize: 18,
      tracking: true
    };
  }

  function defaultActivity() {
    return { version: 1, days: {}, seen: [], books: [] };
  }

  readonly property bool trackingSetting: root.library.tracking !== false
  readonly property bool trackingEnabled: Quickshell.env("DO_NOT_TRACK") !== "1" && root.trackingSetting

  function cssColor(color) {
    function hex(value) {
      var part = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16);
      return part.length < 2 ? "0" + part : part;
    }
    return "#" + hex(color.r) + hex(color.g) + hex(color.b);
  }

  function highlightColor(index) {
    var palette = ["#e5c07b", "#98c379", "#61afef", "#c678dd", "#e06c75", "#d19a66"];
    return palette[index - 1] || root.accent;
  }

  readonly property var htmlOptions: ({
    red: cssColor(root.jesusColor),
    accent: cssColor(root.matchColor),
    redLetters: root.library.redLetters === true
  })

  // ---- State file ------------------------------------------------------
  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: {
      if (root.stateLoaded) return;
      try {
        root.applyState(JSON.parse(text()));
      } catch (e) {
        root.stateLoaded = true;
      }
    }
    onLoadFailed: root.stateLoaded = true
  }

  Timer {
    id: saveTimer
    interval: 350
    onTriggered: root.saveState()
  }

  function applyState(saved) {
    var next = defaultState();
    if (saved && typeof saved === "object") {
      next.translation = saved.translation || next.translation;
      next.last = saved.last || next.last;
      next.highlights = saved.highlights || {};
      next.bookmarks = saved.bookmarks || {};
      next.notes = saved.notes || {};
      next.redLetters = saved.redLetters === true;
      next.fontSize = Math.max(14, Math.min(30, parseInt(saved.fontSize, 10) || 18));
      next.tracking = saved.tracking !== false;
    }
    root.library = next;
    root.translationId = next.translation;
    root.book = next.last.book !== undefined ? next.last.book : 42;
    root.chapter = next.last.chapter !== undefined ? next.last.chapter : 3;
    root.selectedVerse = next.last.verse !== undefined ? next.last.verse : 0;
    root.stateLoaded = true;
    if (root.opened || root.alwaysLoad) {
      root.ensureTranslation();
      if (root.opened) root.recordChapter();
    }
  }

  function saveState() {
    if (!root.stateLoaded) return;
    var saved = {
      version: 1,
      translation: root.translationId,
      last: { book: root.book, chapter: root.chapter, verse: root.selectedVerse },
      highlights: root.library.highlights,
      bookmarks: root.library.bookmarks,
      notes: root.library.notes,
      redLetters: root.library.redLetters === true,
      fontSize: root.library.fontSize,
      tracking: root.library.tracking !== false
    };
    stateFile.setText(JSON.stringify(saved, null, 2) + "\n");
  }

  function saveSoon() { saveTimer.restart(); }

  // ---- Private reading activity ---------------------------------------
  FileView {
    id: activityFile
    path: root.activityPath
    printErrors: false
    onLoaded: {
      if (root.activityLoaded) return;
      try {
        root.applyActivity(JSON.parse(text()));
      } catch (e) {
        root.activityLoaded = true;
      }
    }
    onLoadFailed: root.activityLoaded = true
  }

  Timer {
    id: activitySaveTimer
    interval: 350
    onTriggered: root.saveActivity()
  }

  function applyActivity(saved) {
    var next = defaultActivity();
    if (saved && typeof saved === "object") {
      next.days = saved.days && typeof saved.days === "object" ? saved.days : {};
      next.seen = Array.isArray(saved.seen) ? saved.seen : [];
      next.books = Array.isArray(saved.books) ? saved.books : [];
    }
    root.activity = next;
    root.activityLoaded = true;
    if (root.opened) root.recordChapter();
  }

  function saveActivity() {
    if (!root.activityLoaded) return;
    activityFile.setText(JSON.stringify(root.activity, null, 2) + "\n");
  }

  // One entry per local day, and one unique chapter per day. Chapter keys are
  // references only ("42:3"), never text. This stays on this machine.
  function recordChapter() {
    if (!root.activityLoaded || !root.trackingEnabled) return;
    var key = root.book + ":" + root.chapter;
    var dayKey = Model.dateKey(new Date());
    var days = Object.assign({}, root.activity.days || {});
    var day = Object.assign({ c: 0, k: [] }, days[dayKey] || {});
    day.k = (day.k || []).slice();
    if (day.k.indexOf(key) < 0) day.k.push(key);
    day.c = Math.max(day.c || 0, day.k.length);
    days[dayKey] = day;

    var seen = (root.activity.seen || []).slice();
    if (seen.indexOf(key) < 0) seen.push(key);
    var books = (root.activity.books || []).slice();
    if (books.indexOf(root.book) < 0) books.push(root.book);

    root.activity = Object.assign({}, root.activity, { version: 1, days: days, seen: seen, books: books });
    activitySaveTimer.restart();
    if (root.mode === "stats") root.refreshStats();
  }

  function refreshStats() {
    root.statsView = Model.activityView(root.activity, new Date());
  }

  function openStats() {
    if (root.mode === "stats") {
      root.back();
      return;
    }
    root.mode = "stats";
    root.statsHover = -1;
    root.refreshStats();
    Qt.callLater(function() { catcher.forceActiveFocus(); });
  }

  function toggleTracking() {
    root.library = Object.assign({}, root.library, { tracking: !root.trackingSetting });
    root.saveSoon();
  }

  // ---- Translation data ------------------------------------------------
  function dataPath(id) {
    return decodeURIComponent(String(Qt.resolvedUrl("data/" + id + ".json")).replace(/^file:\/\//, ""));
  }

  function ensureTranslation() {
    if ((!root.opened && !root.alwaysLoad) || root.loadingId === root.translationId && root.loading) return;
    if (root.translation && root.translation.id === root.translationId) {
      root.rebuild();
      return;
    }
    if (root.cache[root.translationId]) {
      root.adopt(root.cache[root.translationId]);
      return;
    }
    root.loading = true;
    root.loadError = "";
    root.loadingId = root.translationId;
    bibleFile.path = root.dataPath(root.translationId);
  }

  function adopt(data) {
    if (!data || !data.chapters) return;
    root.cache[data.id] = data;
    var order = root.cacheOrder.filter(function(id) { return id !== data.id; });
    order.push(data.id);
    while (order.length > 2) {
      var drop = order.shift();
      if (drop !== root.translationId && root.cache[drop]) delete root.cache[drop];
    }
    root.cacheOrder = order;
    // A slow read can finish after the reader moved to another translation.
    // Keep it cached, but do not replace the text on screen.
    if (data.id !== root.translationId) return;
    root.translation = data;
    root.loading = false;
    root.loadingId = "";
    root.loadError = "";
    root.rebuild();
    if (root.mode === "search" && root.query) root.runSearch();
  }

  FileView {
    id: bibleFile
    printErrors: false
    onLoaded: {
      var parsed = null;
      try { parsed = JSON.parse(text()); } catch (e) { root.loadError = "The " + Model.translationAbbrev(root.translationId) + " data is unreadable."; }
      if (parsed) root.adopt(parsed);
    }
    onLoadFailed: {
      root.loading = false;
      root.loadingId = "";
      root.loadError = "Could not load " + Model.translationAbbrev(root.translationId) + ".";
    }
  }

  function rebuild() {
    if (!root.translation) { root.chapterItems = []; return; }
    root.chapterItems = Model.chapterItems(root.translation, root.book, root.chapter, root.htmlOptions);
    Qt.callLater(function() {
      if (verseList) verseList.forceLayout();
      if (root.selectedVerse > 0) root.scrollToVerse(root.selectedVerse);
    });
  }

  function scrollToVerse(number) {
    if (!root.chapterItems || number <= 0) return;
    for (var i = 0; i < root.chapterItems.length; i++) {
      var item = root.chapterItems[i];
      if (item.type === "verse" && item.number === number) {
        verseList.positionViewAtIndex(i, ListView.Beginning);
        return;
      }
    }
  }

  function searchIndexFor(data) {
    if (root.searchIndexId !== data.id) {
      root.searchIndex = Model.buildSearchIndex(data);
      root.searchIndexId = data.id;
    }
    return root.searchIndex;
  }

  // ---- Navigation ------------------------------------------------------
  function goTo(bookIndex, chapterNumber, verseNumber) {
    root.book = Model.clamp(bookIndex, 0, Model.BOOKS.length - 1);
    root.chapter = Model.clamp(chapterNumber, 1, Model.BOOKS[root.book].chapters);
    root.selectedVerse = verseNumber || 0;
    root.mode = "read";
    root.editingNote = false;
    root.library.last = { book: root.book, chapter: root.chapter, verse: root.selectedVerse };
    root.recordChapter();
    root.rebuild();
    root.saveSoon();
    Qt.callLater(function() { catcher.forceActiveFocus(); });
  }

  function stepChapter(delta) {
    var flat = Model.chapterIndex(root.book, root.chapter) + delta;
    flat = Model.clamp(flat, 0, 1188);
    for (var b = 0; b < Model.BOOKS.length; b++) {
      if (flat < Model.OFFSETS[b + 1]) {
        root.goTo(b, flat - Model.OFFSETS[b] + 1, 0);
        return;
      }
    }
  }

  function moveSelection(delta) {
    if (!root.chapterItems.length) return;
    var current = -1;
    for (var i = 0; i < root.chapterItems.length; i++) {
      if (root.chapterItems[i].type === "verse" && root.chapterItems[i].number === root.selectedVerse) { current = i; break; }
    }
    var next = current;
    if (next < 0) next = delta > 0 ? -1 : root.chapterItems.length;
    do { next += delta > 0 ? 1 : -1; } while (next >= 0 && next < root.chapterItems.length && root.chapterItems[next].type !== "verse");
    if (next < 0 || next >= root.chapterItems.length) return;
    root.selectedVerse = root.chapterItems[next].number;
    root.library.last.verse = root.selectedVerse;
    root.saveSoon();
    verseList.positionViewAtIndex(next, ListView.Containing);
  }

  function selectVerse(number) {
    root.selectedVerse = number;
    root.library.last.verse = number;
    root.saveSoon();
  }

  function switchTranslation(id) {
    if (root.translationId === id) return;
    root.translationId = id;
    root.library.translation = id;
    root.saveSoon();
    root.ensureTranslation();
  }

  function cycleTranslation() {
    var ids = [];
    for (var i = 0; i < Model.TRANSLATIONS.length; i++) ids.push(Model.TRANSLATIONS[i].id);
    var at = ids.indexOf(root.translationId);
    root.switchTranslation(ids[(at + 1) % ids.length]);
  }

  function selectedKey() {
    return root.selectedVerse > 0 ? Model.verseKey(root.book, root.chapter, root.selectedVerse) : "";
  }

  function selectedVerseData() {
    var verses = Model.chapterVerses(root.translation, root.book, root.chapter);
    for (var i = 0; i < verses.length; i++) if (verses[i][0] === root.selectedVerse) return verses[i];
    return null;
  }

  // ---- Study: highlights, bookmarks, notes, copy -----------------------
  function setHighlight(color) {
    var key = root.selectedKey();
    if (!key) return;
    var highlights = Object.assign({}, root.library.highlights);
    if (color === 0) delete highlights[key];
    else highlights[key] = color;
    root.library = Object.assign({}, root.library, { highlights: highlights });
    root.saveSoon();
  }

  function toggleBookmark() {
    var key = root.selectedKey();
    if (!key) return;
    var bookmarks = Object.assign({}, root.library.bookmarks);
    if (bookmarks[key]) delete bookmarks[key];
    else bookmarks[key] = Date.now();
    root.library = Object.assign({}, root.library, { bookmarks: bookmarks });
    root.notice = bookmarks[key] ? "Bookmarked " + Model.referenceLabel(root.book, root.chapter, root.selectedVerse) : "Bookmark removed";
    noticeTimer.restart();
    root.saveSoon();
  }

  function startNote() {
    if (!root.selectedVerse) return;
    root.editingNote = true;
    Qt.callLater(function() {
      noteField.text = root.library.notes[root.selectedKey()] || "";
      noteField.forceActiveFocus();
      noteField.selectAll();
    });
  }

  function cancelNote() {
    root.editingNote = false;
    Qt.callLater(function() { catcher.forceActiveFocus(); });
  }

  function commitNote() {
    var key = root.selectedKey();
    if (!key) return;
    var notes = Object.assign({}, root.library.notes);
    if (noteField.text.trim() === "") delete notes[key];
    else notes[key] = noteField.text.trim();
    root.library = Object.assign({}, root.library, { notes: notes });
    root.editingNote = false;
    root.notice = "Note saved";
    noticeTimer.restart();
    root.saveSoon();
    Qt.callLater(function() { catcher.forceActiveFocus(); });
  }

  function copyVerse() {
    var verse = root.selectedVerseData();
    if (!verse) return;
    var reference = Model.referenceLabel(root.book, root.chapter, root.selectedVerse, verse[1]);
    copyProc.command = ["wl-copy", Model.plainText(verse) + " (" + reference + ")"];
    copyProc.running = true;
    root.notice = "Copied " + reference;
    noticeTimer.restart();
  }

  function toggleRedLetters() {
    root.library = Object.assign({}, root.library, { redLetters: root.library.redLetters === false });
    root.rebuild();
    root.saveSoon();
  }

  function adjustFont(delta) {
    var size = Model.clamp((root.library.fontSize || 18) + delta, 14, 30);
    if (size === root.library.fontSize) return;
    root.library = Object.assign({}, root.library, { fontSize: size });
    root.saveSoon();
  }

  // ---- Modes -----------------------------------------------------------
  function openSearch() {
    root.mode = "search";
    root.query = "";
    root.results = [];
    root.resultIndex = 0;
    Qt.callLater(function() {
      searchField.text = "";
      searchField.forceActiveFocus();
    });
  }

  function runSearch() {
    if (!root.translation || !root.query) { root.results = []; return; }
    root.results = Model.search(root.searchIndexFor(root.translation), root.query, root.htmlOptions, 80);
    root.resultIndex = 0;
  }

  function openResult(index) {
    if (!root.results.length) return;
    root.resultIndex = Model.clamp(index, 0, root.results.length - 1);
    var hit = root.results[root.resultIndex];
    root.goTo(hit.book, hit.chapter, hit.number);
  }

  function moveResult(delta) {
    if (!root.results.length) return;
    root.resultIndex = (root.resultIndex + delta + root.results.length) % root.results.length;
    resultsList.positionViewAtIndex(root.resultIndex, ListView.Containing);
  }

  function openJump() {
    root.mode = "jump";
    root.jumpRef = null;
    root.jumpPreview = "";
    Qt.callLater(function() {
      jumpField.text = "";
      jumpField.forceActiveFocus();
    });
  }

  function updateJump() {
    root.jumpRef = Model.parseReference(jumpField.text, root.book);
    root.jumpPreview = root.jumpRef
      ? Model.referenceLabel(root.jumpRef.book, root.jumpRef.chapter, root.jumpRef.verse, root.jumpRef.end)
      : "";
  }

  function confirmJump() {
    if (!root.jumpRef) return;
    root.goTo(root.jumpRef.book, root.jumpRef.chapter, root.jumpRef.verse);
  }

  function openBooks() {
    root.mode = "books";
    root.pickerBook = root.book;
    Qt.callLater(function() {
      booksList.positionViewAtIndex(root.pickerBook, ListView.Containing);
      catcher.forceActiveFocus();
    });
  }

  function back() {
    if (root.editingNote) { root.cancelNote(); return; }
    if (root.mode !== "read") {
      root.mode = "read";
      root.editingNote = false;
      Qt.callLater(function() { catcher.forceActiveFocus(); });
      return;
    }
    root.close();
  }

  function handleMove(dx, dy) {
    if (root.mode === "search") { if (dy) root.moveResult(dy); return; }
    if (root.mode === "books") {
      if (dy) root.pickerBook = Model.clamp(root.pickerBook + dy, 0, Model.BOOKS.length - 1);
      return;
    }
    if (root.mode === "stats") {
      if (dy) statsFlickable.contentY = Model.clamp(statsFlickable.contentY + dy * Style.space(48), 0,
        Math.max(0, statsFlickable.contentHeight - statsFlickable.height));
      return;
    }
    if (root.mode !== "read") return;
    if (dy) root.moveSelection(dy);
    if (dx) root.stepChapter(dx);
  }

  function handleText(text) {
    if (root.mode !== "read") return;
    if (text === "g" || text === "G") root.openJump();
    else if (text === "c" || text === "C") root.openBooks();
    else if (text === "s" || text === "S") root.openStats();
    else if (text === "/" || text === "?") root.openSearch();
    else if (text === "t" || text === "T") root.cycleTranslation();
    else if (text === "b" || text === "B") root.toggleBookmark();
    else if (text === "n" || text === "N") root.startNote();
    else if (text === "y" || text === "Y") root.copyVerse();
    else if (text === "r" || text === "R") root.toggleRedLetters();
    else if (text === "+" || text === "=") root.adjustFont(1);
    else if (text === "-" || text === "_") root.adjustFont(-1);
    else if (text === "[") root.stepChapter(-1);
    else if (text === "]") root.stepChapter(1);
    else if (text >= "1" && text <= "6") root.setHighlight(parseInt(text, 10));
    else if (text === "0") root.setHighlight(0);
  }

  // ---- Bar lifecycle ---------------------------------------------------
  onOpenedChanged: {
    if (root.opened) {
      root.ensureTranslation();
      root.recordChapter();
      Qt.callLater(function() {
        catcher.forceActiveFocus();
        if (root.mode === "read" && root.selectedVerse > 0) root.scrollToVerse(root.selectedVerse);
      });
    } else {
      root.editingNote = false;
      root.mode = "read";
      root.saveState();
      root.saveActivity();
    }
  }

  onBookChanged: saveSoon()
  onChapterChanged: saveSoon()
  onSelectedVerseChanged: saveSoon()

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.stateDir]);
    stateFile.reload();
    activityFile.reload();
  }

  Timer { id: noticeTimer; interval: 1600; onTriggered: root.notice = "" }

  Process { id: copyProc }

  FontLoader { id: literata; source: Qt.resolvedUrl("fonts/Literata.ttf") }
  FontLoader { id: literataItalic; source: Qt.resolvedUrl("fonts/Literata-Italic.ttf") }

  // The bar mark. Left click opens the reader.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.fg
    tooltipText: "Bible — " + Model.referenceLabel(root.book, root.chapter, root.selectedVerse)
    text: "\uf02d"
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.toggle();
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    centerOnBar: true
    padding: 0
    contentWidth: panel.fittedContentWidth(Style.space(760))
    contentHeight: panel.fittedContentHeight(Style.space(640))

    Rectangle {
      anchors.fill: parent
      color: root.surface
      radius: Style.cornerRadius
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      PanelKeyCatcher {
        id: catcher
        anchors.fill: parent
        blocked: searchField.activeFocus || jumpField.activeFocus || noteField.activeFocus
        onMoveRequested: function(dx, dy) { root.handleMove(dx, dy) }
        onCloseRequested: root.back()
        onReturnRequested: {
          if (root.mode === "search") root.openResult(root.resultIndex);
          else if (root.mode === "jump") root.confirmJump();
          else if (root.mode === "read" && root.selectedVerse > 0) root.copyVerse();
        }
        onTabRequested: function(direction) { root.switchPanel(direction) }
        onTextKey: function(text) { root.handleText(text) }
      }

      Timer {
        id: searchDebounce
        interval: 120
        onTriggered: root.runSearch()
      }

      // ---- Header ------------------------------------------------------
      Item {
        id: header
        height: Style.space(92)
        anchors { left: parent.left; right: parent.right; top: parent.top }

        Item {
          id: titleRow
          height: Style.space(54)
          anchors { left: parent.left; right: parent.right; top: parent.top }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              iconText: "󰅁"
              tooltipText: "Previous chapter"
              foreground: root.fg
              fontFamily: root.uiFont
              onClicked: root.stepChapter(-1)
            }

            Item {
              width: title.implicitWidth + Style.space(8)
              height: Style.space(36)

              Text {
                id: title
                anchors.centerIn: parent
                text: Model.chapterLabel(root.book, root.chapter)
                color: root.fg
                font.family: root.serif
                font.pixelSize: Style.font.title
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openBooks()
              }
            }

            PanelActionButton {
              iconText: "󰅂"
              tooltipText: "Next chapter"
              foreground: root.fg
              fontFamily: root.uiFont
              onClicked: root.stepChapter(1)
            }
          }

          PanelActionButton {
            id: searchButton
            anchors.right: parent.right
            anchors.rightMargin: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰍉"
            tooltipText: "Search (/)"
            foreground: root.fg
            fontFamily: root.uiFont
            onClicked: root.openSearch()
          }

          PanelActionButton {
            anchors.right: searchButton.left
            anchors.verticalCenter: parent.verticalCenter
            iconText: "▦"
            tooltipText: "Reading activity (s)"
            foreground: root.fg
            fontFamily: root.uiFont
            onClicked: root.openStats()
          }
        }

        Row {
          id: translationRow
          height: Style.space(30)
          anchors {
            left: parent.left
            right: parent.right
            top: titleRow.bottom
          }
          anchors.leftMargin: root.gutter
          anchors.rightMargin: root.gutter
          spacing: Style.space(2)

          Repeater {
            model: Model.TRANSLATIONS

            Rectangle {
              required property var modelData
              width: label.implicitWidth + Style.space(10)
              height: Style.space(22)
              y: Math.round((translationRow.height - height) / 2)
              radius: Style.cornerRadius
              color: root.translationId === modelData.id
                ? Util.alpha(root.accent, 0.18)
                : (translationMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")

              Text {
                id: label
                anchors.centerIn: parent
                text: modelData.abbrev
                color: root.translationId === modelData.id ? root.accent : Qt.darker(root.fg, 1.35)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.5
              }

              MouseArea {
                id: translationMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchTranslation(modelData.id)
              }
            }
          }
        }

        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: Style.spacing.hairline
          color: root.fg
          opacity: 0.12
        }
      }

      // ---- Reader ------------------------------------------------------
      Item {
        id: contentArea
        anchors {
          left: parent.left
          right: parent.right
          top: header.bottom
          bottom: footer.top
        }

        ListView {
          id: verseList
          anchors.fill: parent
          anchors.leftMargin: root.gutter
          anchors.rightMargin: root.gutter
          anchors.topMargin: Style.space(8)
          anchors.bottomMargin: Style.space(8)
          clip: true
          model: root.chapterItems
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          cacheBuffer: 900
          visible: root.mode === "read"

          delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: verseList.width
            height: modelData.type === "heading"
              ? headingText.height + Style.space(14)
              : Math.max(bodyText.height, numberText.height) + Style.space(6)
            readonly property bool isVerse: modelData.type === "verse"
            readonly property string key: isVerse ? Model.verseKey(root.book, root.chapter, modelData.number) : ""
            readonly property int highlight: isVerse ? (root.library.highlights[key] || 0) : 0
            readonly property bool selected: isVerse && root.selectedVerse === modelData.number

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: row.selected
                ? Util.alpha(root.accent, 0.10)
                : (row.highlight > 0 ? Util.alpha(root.highlightColor(row.highlight), 0.18) : "transparent")
            }

            Rectangle {
              visible: row.selected
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Math.max(1, Style.space(2))
              color: root.accent
            }

            Text {
              id: numberText
              visible: row.isVerse
              width: Style.space(30)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.top: parent.top
              anchors.topMargin: Style.space(4)
              horizontalAlignment: Text.AlignRight
              text: row.isVerse ? (modelData.end !== modelData.number ? modelData.number + "-" + modelData.end : modelData.number) : ""
              color: row.highlight > 0 ? Qt.darker(root.highlightColor(row.highlight), 1.15) : root.muted
              font.family: root.uiFont
              font.pixelSize: Math.max(9, Math.round(root.library.fontSize * 0.58))
              font.bold: row.selected
            }

            Text {
              id: bodyText
              visible: row.isVerse
              x: Style.space(40)
              width: parent.width - x - Style.space(24)
              textFormat: Text.RichText
              text: row.isVerse ? modelData.html : ""
              color: root.fg
              linkColor: root.accent
              font.family: root.serif
              font.pixelSize: root.library.fontSize
              lineHeight: 1.35
              wrapMode: Text.WordWrap
            }

            Text {
              visible: row.isVerse === true && row.key !== "" && (root.library.bookmarks[row.key] !== undefined || root.library.notes[row.key] !== undefined)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.top: parent.top
              anchors.topMargin: Style.space(4)
              text: row.isVerse
                ? ((root.library.bookmarks[row.key] ? "\uf02e" : "") + (root.library.notes[row.key] ? "  \uf040" : ""))
                : ""
              color: root.accent
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
            }

            Text {
              id: headingText
              visible: !row.isVerse
              width: parent.width - Style.space(40)
              x: Style.space(40)
              text: row.isVerse ? "" : modelData.text
              textFormat: Text.PlainText
              color: modelData.level === 3 ? root.muted : root.fg
              font.family: root.serif
              font.pixelSize: modelData.level === 1 ? root.library.fontSize + 2 : root.library.fontSize
              font.bold: modelData.level !== 3
              font.italic: modelData.level === 3
              font.capitalization: modelData.level === 1 ? Font.AllUppercase : Font.MixedCase
              wrapMode: Text.WordWrap
              topPadding: Style.space(10)
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              onClicked: if (row.isVerse) root.selectVerse(modelData.number)
              onDoubleClicked: if (row.isVerse) { root.selectVerse(modelData.number); root.copyVerse(); }
            }
          }
        }

        Text {
          visible: root.loading && root.mode === "read"
          anchors.centerIn: parent
          text: "Loading " + Model.translationAbbrev(root.translationId) + "…"
          color: root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.body
        }

        Text {
          visible: root.loadError !== "" && root.mode === "read"
          anchors.centerIn: parent
          width: parent.width - root.gutter * 2
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.loadError
          color: root.urgent
          font.family: root.uiFont
          font.pixelSize: Style.font.body
        }

        // ---- Search ----------------------------------------------------
        Item {
          id: searchView
          anchors.fill: parent
          visible: root.mode === "search"

          Item {
            id: searchBar
            height: Style.space(54)
            anchors { left: parent.left; right: parent.right; top: parent.top }

            TextField {
              id: searchField
              anchors.left: parent.left
              anchors.leftMargin: root.gutter
              anchors.right: countText.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "Search the Bible — \"exact phrase\", -exclude"
              foreground: root.fg
              font.family: root.uiFont
              onTextChanged: { root.query = text; searchDebounce.restart(); }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; }
                else if (event.key === Qt.Key_Down) { root.moveResult(1); event.accepted = true; }
                else if (event.key === Qt.Key_Up) { root.moveResult(-1); event.accepted = true; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openResult(root.resultIndex); event.accepted = true; }
              }
            }

            Text {
              id: countText
              anchors.right: parent.right
              anchors.rightMargin: root.gutter
              anchors.verticalCenter: parent.verticalCenter
              text: root.query ? root.results.length + (root.results.length === 80 ? "+" : "") : ""
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
              height: Style.spacing.hairline
              color: root.fg
              opacity: 0.08
            }
          }

          ListView {
            id: resultsList
            anchors { left: parent.left; right: parent.right; top: searchBar.bottom; bottom: parent.bottom }
            anchors.leftMargin: root.gutter
            anchors.rightMargin: root.gutter
            clip: true
            model: root.results
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: resultRow
              required property var modelData
              required property int index
              width: resultsList.width
              height: resultColumn.height + Style.space(16)
              radius: Style.cornerRadius
              color: index === root.resultIndex ? Util.alpha(root.accent, 0.10) : "transparent"

              Column {
                id: resultColumn
                x: Style.space(10)
                y: Style.space(8)
                width: parent.width - Style.space(20)
                spacing: Style.space(3)

                Text {
                  text: modelData.reference
                  color: index === root.resultIndex ? root.accent : root.fg
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  textFormat: Text.RichText
                  text: modelData.snippet
                  color: Qt.darker(root.fg, 1.2)
                  font.family: root.serif
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { root.resultIndex = index; root.openResult(index); }
                onPositionChanged: root.resultIndex = index
              }
            }
          }

          Text {
            visible: root.query !== "" && root.results.length === 0
            anchors.centerIn: parent
            text: "No verses match."
            color: root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.body
          }
        }

        // ---- Jump to reference ----------------------------------------
        Item {
          id: jumpView
          anchors.fill: parent
          visible: root.mode === "jump"

          Column {
            anchors.top: parent.top
            anchors.topMargin: Style.space(28)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - root.gutter * 2, Style.space(520))
            spacing: Style.space(10)

            TextField {
              id: jumpField
              width: parent.width
              placeholderText: "jn 3:16 · Rom 8 · 1co13 · revalation 21"
              foreground: root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.title
              onTextChanged: root.updateJump()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.confirmJump(); event.accepted = true; }
              }
            }

            Text {
              width: parent.width
              text: root.jumpPreview !== "" ? "→ " + root.jumpPreview : "Type a book, chapter and verse. Typos are forgiven."
              color: root.jumpPreview !== "" ? root.accent : root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        // ---- Book and chapter picker ------------------------------------
        Item {
          id: booksView
          anchors.fill: parent
          visible: root.mode === "books"

          Row {
            anchors.fill: parent
            anchors.margins: root.gutter
            spacing: Style.space(16)

            ListView {
              id: booksList
              width: Math.min(Style.space(250), Math.round(parent.width * 0.36))
              height: parent.height
              clip: true
              model: Model.BOOKS
              spacing: Style.space(1)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: booksList.width
                height: Style.space(28)
                radius: Style.cornerRadius
                color: index === root.pickerBook
                  ? Util.alpha(root.accent, 0.16)
                  : (bookMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (index < 39 ? "OT" : "NT") + "  " + modelData.name
                  color: index === root.pickerBook ? root.accent : root.fg
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  font.bold: index === root.pickerBook
                }

                MouseArea {
                  id: bookMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: { root.pickerBook = index; catcher.forceActiveFocus(); }
                }
              }
            }

            Column {
              width: parent.width - booksList.width - parent.spacing
              height: parent.height
              spacing: Style.space(12)

              Text {
                text: Model.bookName(root.pickerBook).toUpperCase()
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.5
              }

              GridView {
                id: chaptersGrid
                width: parent.width
                height: parent.height - Style.space(28)
                cellWidth: Math.max(1, Math.floor(width / 7))
                cellHeight: Math.max(Style.space(30), Math.round(cellWidth * 0.55))
                clip: true
                model: root.pickerBook >= 0 ? Model.BOOKS[root.pickerBook].chapters : 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  required property int index
                  width: chaptersGrid.cellWidth - Math.max(2, Math.round(chaptersGrid.cellWidth * 0.06))
                  height: chaptersGrid.cellHeight - Math.max(2, Math.round(chaptersGrid.cellHeight * 0.08))
                  radius: Style.cornerRadius
                  color: index + 1 === root.chapter && root.book === root.pickerBook
                    ? Util.alpha(root.accent, 0.18)
                    : (chapterMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")

                  Text {
                    anchors.centerIn: parent
                    text: index + 1
                    color: index + 1 === root.chapter && root.book === root.pickerBook ? root.accent : root.fg
                    font.family: root.uiFont
                    font.pixelSize: Style.font.body
                    font.bold: index + 1 === root.chapter && root.book === root.pickerBook
                  }

                  MouseArea {
                    id: chapterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.goTo(root.pickerBook, index + 1, 0)
                  }
                }
              }
            }
          }
        }

        // ---- Reading activity ------------------------------------------
        Item {
          id: statsPage
          anchors.fill: parent
          visible: root.mode === "stats"

          readonly property var v: root.statsView || ({})
          readonly property int cols: Math.max(1, Math.ceil(((v.cells || []).length) / 7))
          readonly property real cell: Math.min(Style.space(10),
            Math.max(6, (width - 2 * root.gutter - (cols - 1) * Style.space(3)) / cols))

          Flickable {
            id: statsFlickable
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: statsColumn.implicitHeight + Style.space(16)
            boundsBehavior: Flickable.StopAtBounds

          Column {
            id: statsColumn
            x: root.gutter
            y: Style.space(8)
            width: parent.width - 2 * root.gutter
            spacing: Style.space(7)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "READING ACTIVITY"
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: statsPage.v.since || ""
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              spacing: Style.space(34)

              Repeater {
                model: [
                  { value: statsPage.v.chapters || 0, label: "chapters" },
                  { value: statsPage.v.activeDays || 0, label: "active days" },
                  { value: statsPage.v.streak || 0, label: "day streak" },
                  { value: statsPage.v.week || 0, label: "this week" }
                ]

                Column {
                  required property var modelData
                  spacing: Style.space(1)

                  Text {
                    text: String(modelData.value)
                    color: root.fg
                    font.family: root.serif
                    font.pixelSize: Style.font.title + 6
                    font.bold: true
                  }

                  Text {
                    text: modelData.label
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 0.5
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: activityGrid.height + Style.space(22)

              Grid {
                id: activityGrid
                rows: 7
                flow: Grid.TopToBottom
                spacing: Style.space(3)

                Repeater {
                  model: (statsPage.v.cells || []).length

                  Rectangle {
                    required property int index
                    readonly property int level: (statsPage.v.cells || [])[index]
                    width: statsPage.cell
                    height: statsPage.cell
                    radius: 2
                    color: level < 0 ? "transparent" : Util.alpha(root.accent, [0.07, 0.25, 0.45, 0.7, 0.95][level])
                    border.width: root.statsHover === index ? 1 : 0
                    border.color: root.fg

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onEntered: root.statsHover = index
                      onExited: if (root.statsHover === index) root.statsHover = -1
                    }
                  }
                }
              }

              Item {
                anchors.top: activityGrid.bottom
                anchors.topMargin: Style.space(5)
                width: parent.width
                height: Style.space(14)

                Repeater {
                  model: statsPage.v.months || []

                  Text {
                    required property var modelData
                    x: modelData.col * (statsPage.cell + Style.space(3))
                    text: modelData.label
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption - 1
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: {
                var labels = statsPage.v.labels || [];
                if (!labels.length) return "Open a chapter to start the grid.";
                if (root.statsHover >= 0 && labels[root.statsHover]) return labels[root.statsHover];
                return "today · " + labels[labels.length - 1];
              }
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              width: parent.width
              height: privacy.height + Style.space(20)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.04)

              Item {
                id: privacy
                x: Style.space(10)
                y: Style.space(10)
                width: parent.width - Style.space(20)
                height: privacyText.height

                Column {
                  id: privacyText
                  width: parent.width - toggle.width - Style.space(12)
                  spacing: Style.space(3)

                  Text {
                    text: "PRIVATE TRACKING"
                    color: root.accent
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  Text {
                    width: parent.width
                    text: "Dates, chapter references and counts only. No verse text, notes, account or network."
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    width: parent.width
                    text: "~/.local/state/omarchy/bible-activity.json"
                    color: Qt.darker(root.muted, 1.2)
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption - 1
                    elide: Text.ElideMiddle
                  }
                }

                Rectangle {
                  id: toggle
                  width: Style.space(34)
                  height: Style.space(18)
                  anchors.right: parent.right
                  anchors.top: parent.top
                  radius: height / 2
                  color: root.trackingEnabled ? Util.alpha(root.accent, 0.75) : Util.alpha(root.fg, 0.15)

                  Rectangle {
                    width: parent.height - Style.space(4)
                    height: width
                    y: Style.space(2)
                    x: root.trackingEnabled ? parent.width - width - Style.space(2) : Style.space(2)
                    radius: width / 2
                    color: root.fg
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleTracking()
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.top: parent.bottom
                    anchors.topMargin: Style.space(2)
                    text: Quickshell.env("DO_NOT_TRACK") === "1" ? "forced off" : (root.trackingEnabled ? "on" : "off")
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption - 1
                  }
                }
              }
            }
          }
          }
        }
      }

      // ---- Footer ------------------------------------------------------
      Rectangle {
        id: footer
        height: root.footerHeight
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        color: Util.alpha(root.fg, 0.04)

        Rectangle {
          anchors { left: parent.left; right: parent.right; top: parent.top }
          height: Style.spacing.hairline
          color: root.fg
          opacity: 0.12
        }

        Text {
          visible: (root.mode !== "read" || root.selectedVerse === 0) && !root.editingNote
          anchors.left: parent.left
          anchors.leftMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter
          text: root.mode === "read"
            ? "j/k verse · h/l chapter · g go · / search · s activity"
            : "Esc back"
          color: root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
        }

        Row {
          visible: root.mode === "read" && root.selectedVerse > 0 && !root.editingNote
          anchors.left: parent.left
          anchors.leftMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Text {
            text: Model.referenceLabel(root.book, root.chapter, root.selectedVerse)
            color: root.accent
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Row {
            spacing: Style.space(6)

            Repeater {
              model: 6

              Rectangle {
                required property int index
                width: Style.space(14)
                height: width
                radius: width / 2
                color: root.highlightColor(index + 1)
                border.width: root.library.highlights[root.selectedKey()] === index + 1 ? Math.max(1, Style.space(2)) : 0
                border.color: root.fg

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setHighlight(index + 1)
                }
              }
            }

            Text {
              text: "0"
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setHighlight(0)
              }
            }
          }
        }

        Row {
          visible: root.mode === "read" && root.selectedVerse > 0 && !root.editingNote
          anchors.right: parent.right
          anchors.rightMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          PanelActionButton {
            iconText: "\uf02e"
            tooltipText: root.library.bookmarks[root.selectedKey()] ? "Remove bookmark" : "Bookmark (b)"
            foreground: root.library.bookmarks[root.selectedKey()] ? root.accent : root.fg
            fontFamily: root.uiFont
            onClicked: root.toggleBookmark()
          }

          PanelActionButton {
            iconText: "\uf040"
            tooltipText: "Note (n)"
            foreground: root.fg
            fontFamily: root.uiFont
            onClicked: root.startNote()
          }

          PanelActionButton {
            iconText: "\uf0c5"
            tooltipText: "Copy verse (y)"
            foreground: root.fg
            fontFamily: root.uiFont
            onClicked: root.copyVerse()
          }
        }

        Item {
          visible: root.editingNote
          anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
          anchors.leftMargin: root.gutter
          anchors.rightMargin: root.gutter

          Text {
            id: noteLabel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: Style.space(10)
            text: "NOTE · " + Model.referenceLabel(root.book, root.chapter, root.selectedVerse)
            color: root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          TextField {
            id: noteField
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: noteLabel.bottom
            anchors.topMargin: Style.space(6)
            placeholderText: "Write a note, Enter to save"
            foreground: root.fg
            font.family: root.uiFont
            onAccepted: root.commitNote()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.cancelNote(); event.accepted = true; }
            }
          }
        }

        Text {
          visible: root.notice !== ""
          anchors.right: parent.right
          anchors.rightMargin: root.gutter
          anchors.bottom: parent.top
          text: root.notice
          color: root.accent
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
