import QtQuick
import Quickshell
import qs.Ui

Item {
  id: root
  property QtObject bar: null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Bible"
    text: "\uf02d"
    onPressed: function(button) {
      if (button === Qt.LeftButton)
        Quickshell.execDetached(["omarchy-shell", "shell", "summon", "sero.bible", "{}"]);
    }
  }
}
