import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: full

  property bool opened: false
  property var shell: null
  property int tab: 0
  property int pickerBook: 42
  property bool sidebarOpen: true
  property bool searchOpen: false
  property var backStack: []
  property var forwardStack: []
  property var studyKeys: []
  property bool studyDirty: true

  readonly property color bg: "#0f0e0d"
  readonly property color surface: "#171412"
  readonly property color raised: "#201c18"
  readonly property color line: "#2a2520"
  readonly property color fg: "#f1ece4"
  readonly property color muted: "#8f877c"
  readonly property color accent: "#d9b56b"
  readonly property string serif: literata.name !== "" ? literata.name : "Georgia"
  readonly property string sans: "Inter"

  FontLoader { id: literata; source: "fonts/Literata.ttf" }

  function open(payloadJson) {
    opened = true;
    sidebarOpen = true;
    core.alwaysLoad = true;
    core.ensureTranslation();
    if (core.stateLoaded) core.goTo(core.book, core.chapter, core.selectedVerse);
    Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
  }

  function close() {
    opened = false;
    if (shell && typeof shell.hide === "function") shell.hide("sero.bible");
  }

  function toggle() {
    if (opened) close();
    else open("{}");
  }

  function referenceForKey(key) {
    var p = String(key).split(":");
    if (p.length < 2) return key;
    return Model.referenceLabel(parseInt(p[0], 10), parseInt(p[1], 10), parseInt(p[2] || "0", 10));
  }

  function go(book, chapter, verse) {
    if (!core) return;
    backStack = backStack.concat([{ book: core.book, chapter: core.chapter, verse: core.selectedVerse }]);
    forwardStack = [];
    core.goTo(book, chapter, verse || 0);
    searchOpen = false;
    studyDirty = true;
  }

  function back() {
    if (!backStack.length) return;
    var to = backStack[backStack.length - 1];
    backStack = backStack.slice(0, -1);
    forwardStack = forwardStack.concat([{ book: core.book, chapter: core.chapter, verse: core.selectedVerse }]);
    core.goTo(to.book, to.chapter, to.verse || 0);
  }

  function forward() {
    if (!forwardStack.length) return;
    var to = forwardStack[forwardStack.length - 1];
    forwardStack = forwardStack.slice(0, -1);
    backStack = backStack.concat([{ book: core.book, chapter: core.chapter, verse: core.selectedVerse }]);
    core.goTo(to.book, to.chapter, to.verse || 0);
  }

  function refreshStudy() {
    var seen = {};
    var out = [];
    function add(key) { if (!seen[key]) { seen[key] = true; out.push(key); } }
    var k;
    for (k in core.library.highlights) add(k);
    for (k in core.library.bookmarks) add(k);
    for (k in core.library.notes) add(k);
    out.sort();
    studyKeys = out;
    studyDirty = false;
  }

  function selectTab(index) {
    tab = index;
    if (index === 2 && studyDirty) refreshStudy();
    if (index === 0) pickerBook = core.book;
  }

  ReaderPanel {
    id: core
    visible: false
    width: 1
    height: 1
    bar: null
    ipcTarget: ""
    manageIpc: false
    alwaysLoad: true
  }

  Connections {
    target: core
    function onStateLoadedChanged() {
      if (core.stateLoaded) {
        core.ensureTranslation();
        if (full.opened) core.rebuild();
      }
    }
    function onLibraryChanged() { full.studyDirty = true; }
    function onTranslationChanged() { if (full.opened) core.rebuild(); }
  }

  Timer {
    interval: 250
    repeat: true
    running: full.opened && (!core.translation || core.loading)
    onTriggered: core.ensureTranslation()
  }

  PanelWindow {
    id: window
    visible: full.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: full.bg
    WlrLayershell.namespace: "omarchy-bible-fullscreen"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (full.searchOpen) full.searchOpen = false;
          else full.close();
          event.accepted = true;
        } else if (event.key === Qt.Key_B && (event.modifiers & Qt.ControlModifier)) {
          full.sidebarOpen = !full.sidebarOpen;
          event.accepted = true;
        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
          full.searchOpen = !full.searchOpen;
          if (full.searchOpen) Qt.callLater(function() { searchField.forceActiveFocus(); });
          event.accepted = true;
        } else if (!full.searchOpen && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
          core.stepChapter(event.key === Qt.Key_Left ? -1 : 1);
          event.accepted = true;
        }
      }

      // ---- toolbar ----------------------------------------------------
      Rectangle {
        id: toolbar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 52
        color: full.surface

        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: 1
          color: full.line
        }

        Row {
          anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
          spacing: 2
          FsIcon {
            glyph: "\uf0c9"
            color: full.muted
            onClicked: full.sidebarOpen = !full.sidebarOpen
          }
          FsIcon {
            glyph: "\uf060"
            color: full.backStack.length ? full.fg : full.line
            onClicked: full.back()
          }
          FsIcon {
            glyph: "\uf061"
            color: full.forwardStack.length ? full.fg : full.line
            onClicked: full.forward()
          }
        }

        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            text: Model.bookName(core.book) + " " + core.chapter
            color: full.fg
            font.family: full.sans
            font.pixelSize: 14
            font.weight: Font.Medium
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                full.selectTab(0);
                full.sidebarOpen = true;
              }
            }
          }
          Text {
            text: "·"
            color: full.muted
            font.pixelSize: 13
          }
          Text {
            text: Model.translationAbbrev(core.translationId)
            color: full.muted
            font.family: full.sans
            font.pixelSize: 12
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: core.cycleTranslation()
            }
          }
        }

        Row {
          anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
          spacing: 2
          FsIcon {
            glyph: "\uf002"
            color: full.muted
            onClicked: {
              full.searchOpen = !full.searchOpen;
              if (full.searchOpen) Qt.callLater(function() { searchField.forceActiveFocus(); });
            }
          }
          FsIcon {
            glyph: "A"
            pixelSize: 15
            color: full.muted
            onClicked: core.adjustFont(1)
          }
          FsIcon {
            glyph: "a"
            pixelSize: 13
            color: full.muted
            onClicked: core.adjustFont(-1)
          }
          FsIcon {
            glyph: "\uf00d"
            color: full.muted
            onClicked: full.close()
          }
        }
      }

      // ---- sidebar ----------------------------------------------------
      Rectangle {
        id: sidebar
        anchors { top: toolbar.bottom; bottom: parent.bottom; left: parent.left }
        width: full.sidebarOpen ? 300 : 0
        visible: width > 0
        color: full.surface
        clip: true

        Rectangle {
          anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
          width: 1
          color: full.line
        }

        Item {
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: 46

          Row {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 18
            Repeater {
              model: ["Books", "Finished", "Study"]
              delegate: Item {
                required property var modelData
                required property int index
                width: tabLabel.width
                height: 40
                Text {
                  id: tabLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData
                  color: full.tab === index ? full.fg : full.muted
                  font.family: full.sans
                  font.pixelSize: 12
                  font.weight: full.tab === index ? Font.Medium : Font.Normal
                }
                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                  height: 1
                  color: full.tab === index ? full.accent : "transparent"
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: full.selectTab(index)
                }
              }
            }
          }
        }

        // Books
        Item {
          anchors { top: parent.top; topMargin: 46; left: parent.left; right: parent.right; bottom: parent.bottom }
          visible: full.tab === 0

          ListView {
            id: bookList
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * 0.52
            clip: true
            model: Model.BOOKS
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: bookList.width
              height: 30
              color: index === full.pickerBook ? full.raised : "transparent"
              Text {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                text: modelData.name
                color: index === full.pickerBook ? full.fg : full.muted
                font.family: full.sans
                font.pixelSize: 12
              }
              Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: modelData.chapters
                color: full.line
                font.family: full.sans
                font.pixelSize: 10
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: full.pickerBook = index
              }
            }
          }

          Rectangle {
            anchors { top: bookList.bottom; left: parent.left; right: parent.right; topMargin: 4 }
            height: 1
            color: full.line
          }

          GridView {
            anchors { top: bookList.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            cellWidth: 36
            cellHeight: 34
            clip: true
            model: Model.BOOKS[full.pickerBook].chapters
            delegate: Rectangle {
              required property int index
              width: 30
              height: 28
              radius: 4
              color: index + 1 === core.chapter && full.pickerBook === core.book ? full.accent : full.raised
              Text {
                anchors.centerIn: parent
                text: index + 1
                color: index + 1 === core.chapter && full.pickerBook === core.book ? full.bg : full.fg
                font.family: full.sans
                font.pixelSize: 11
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: full.go(full.pickerBook, index + 1, 0)
              }
            }
          }
        }

        // Finished
        Item {
          anchors { top: parent.top; topMargin: 46; left: parent.left; right: parent.right; bottom: parent.bottom }
          visible: full.tab === 1

          ListView {
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            model: core.activity.seen
            spacing: 2
            delegate: Rectangle {
              required property var modelData
              width: ListView.view.width
              height: 34
              color: "transparent"
              Text {
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                text: full.referenceForKey(modelData)
                color: full.fg
                font.family: full.sans
                font.pixelSize: 12
              }
              Text {
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                text: "read"
                color: full.muted
                font.family: full.sans
                font.pixelSize: 10
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var p = modelData.split(":");
                  full.go(parseInt(p[0], 10), parseInt(p[1], 10), 0);
                }
              }
            }
          }
          Text {
            anchors.centerIn: parent
            visible: core.activity.seen.length === 0
            text: "No chapters read yet"
            color: full.muted
            font.family: full.sans
            font.pixelSize: 12
          }
        }

        // Study
        Item {
          anchors { top: parent.top; topMargin: 46; left: parent.left; right: parent.right; bottom: parent.bottom }
          visible: full.tab === 2

          ListView {
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            model: full.studyKeys
            spacing: 2
            delegate: Rectangle {
              required property var modelData
              width: ListView.view.width
              height: 34
              color: "transparent"
              Text {
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                text: full.referenceForKey(modelData)
                color: full.fg
                font.family: full.sans
                font.pixelSize: 12
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var p = modelData.split(":");
                  full.go(parseInt(p[0], 10), parseInt(p[1], 10), parseInt(p[2] || "0", 10));
                }
              }
            }
          }
          Text {
            anchors.centerIn: parent
            visible: full.studyKeys.length === 0
            text: "No highlights, notes or bookmarks"
            color: full.muted
            font.family: full.sans
            font.pixelSize: 12
          }
        }
      }

      // ---- search -----------------------------------------------------
      Rectangle {
        id: searchBar
        visible: full.searchOpen
        anchors { top: toolbar.bottom; left: sidebar.right; right: parent.right }
        height: 46
        color: full.surface

        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: 1
          color: full.line
        }

        TextInput {
          id: searchField
          anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
          color: full.fg
          font.family: full.sans
          font.pixelSize: 14
          selectionColor: full.accent
          selectedTextColor: full.bg
          onTextChanged: {
            core.query = text;
            if (text.length) core.runSearch();
          }
          Keys.onEscapePressed: full.searchOpen = false
        }

        Text {
          anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
          visible: searchField.text.length === 0
          text: "Search the Bible…"
          color: full.muted
          font.family: full.sans
          font.pixelSize: 14
        }
      }

      // ---- reader -----------------------------------------------------
      Flickable {
        id: readerScroll
        anchors { top: searchBar.visible ? searchBar.bottom : toolbar.bottom; left: sidebar.right; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: readerColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: readerColumn
          width: Math.min(720, readerScroll.width - 96)
          anchors.horizontalCenter: parent.horizontalCenter
          topPadding: 42
          spacing: 0

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Model.bookName(core.book)
            color: full.fg
            font.family: full.serif
            font.pixelSize: 42
            font.weight: Font.Normal
          }
          Item { width: 1; height: 28 }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "CHAPTER " + core.chapter
            color: full.muted
            font.family: full.sans
            font.pixelSize: 10
            font.letterSpacing: 2
          }
          Item { width: 1; height: 26 }

          Repeater {
            model: core.chapterItems
            delegate: Item {
              id: row
              required property var modelData
              required property int index
              width: readerColumn.width
              height: modelData.type === "verse" ? verseBody.height + 14 : headingText.height + 22

              Text {
                id: headingText
                visible: modelData.type !== "verse"
                x: 36
                width: parent.width - 36
                text: modelData.type !== "verse" ? modelData.text : ""
                color: modelData.level === 3 ? full.muted : full.fg
                font.family: full.serif
                font.pixelSize: modelData.level === 1 ? 20 : 16
                font.bold: modelData.level !== 3
                font.italic: modelData.level === 3
                font.capitalization: modelData.level === 1 ? Font.AllUppercase : Font.MixedCase
                wrapMode: Text.WordWrap
              }

              Rectangle {
                id: highlight
                visible: modelData.type === "verse" &&
                  core.library.highlights[Model.verseKey(core.book, core.chapter, modelData.number)] !== undefined
                anchors.fill: verseBody
                color: visible ? full.accent : "transparent"
                opacity: 0.12
                radius: 3
              }

              Rectangle {
                visible: modelData.type === "verse" && core.selectedVerse === modelData.number
                anchors.fill: verseBody
                color: "transparent"
                border.width: 1
                border.color: full.accent
                radius: 3
              }

              Text {
                visible: modelData.type === "verse"
                x: 0
                width: 28
                y: verseBody.y
                horizontalAlignment: Text.AlignRight
                text: modelData.type === "verse" ? modelData.number : ""
                color: full.muted
                font.family: full.serif
                font.pixelSize: 11
              }

              Text {
                id: verseBody
                visible: modelData.type === "verse"
                x: 36
                width: parent.width - 36
                text: modelData.type === "verse" ? modelData.html : ""
                textFormat: Text.RichText
                color: full.fg
                linkColor: full.accent
                font.family: full.serif
                font.pixelSize: core.library.fontSize
                lineHeight: 1.42
                wrapMode: Text.WordWrap
              }

              Text {
                visible: modelData.type === "verse" &&
                  (core.library.bookmarks[Model.verseKey(core.book, core.chapter, modelData.number)] !== undefined ||
                   core.library.notes[Model.verseKey(core.book, core.chapter, modelData.number)] !== undefined)
                anchors { right: parent.right; top: parent.top; topMargin: 4 }
                text: (core.library.bookmarks[Model.verseKey(core.book, core.chapter, modelData.number)] ? "\uf02e" : "") +
                      (core.library.notes[Model.verseKey(core.book, core.chapter, modelData.number)] ? "  \uf040" : "")
                color: full.accent
                font.family: full.sans
                font.pixelSize: 10
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: if (modelData.type === "verse") core.selectVerse(modelData.number)
                onDoubleClicked: if (modelData.type === "verse") { core.selectVerse(modelData.number); core.copyVerse(); }
              }
            }
          }

          Item { width: 1; height: 90 }
        }
      }

      Text {
        anchors.centerIn: readerScroll
        visible: core.loading
        text: "Loading " + Model.translationAbbrev(core.translationId) + "…"
        color: full.muted
        font.family: full.sans
        font.pixelSize: 13
      }

      Text {
        anchors.centerIn: readerScroll
        visible: !core.loading && core.loadError !== ""
        width: readerScroll.width - 80
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: core.loadError
        color: "#e06c75"
        font.family: full.sans
        font.pixelSize: 13
      }
    }
  }

  onOpenedChanged: {
    if (opened) {
      core.ensureTranslation();
      Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
    }
  }
}
