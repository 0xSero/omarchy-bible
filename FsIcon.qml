import QtQuick

Item {
  id: root
  property string glyph: ""
  property color color: "#d8d2c8"
  property int pixelSize: 18
  signal clicked()

  implicitWidth: 34
  implicitHeight: 34

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: area.containsMouse ? "#201c18" : "transparent"
  }
  Text {
    anchors.centerIn: parent
    text: root.glyph
    color: root.color
    font.pixelSize: root.pixelSize
    font.family: "Inter"
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
