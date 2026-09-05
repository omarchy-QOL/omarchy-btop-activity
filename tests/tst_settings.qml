import QtQuick
import QtTest
import "../lib/Settings.js" as Settings

TestCase {
  name: "Settings"

  readonly property string shipped: '# comment\npoll_intervals = [250, 500, 1000, 2000, 5000]\nleft_click = "open"\n'

  function test_shipped_file() {
    var settings = Settings.parse(shipped)
    compare(settings.pollIntervals, [250, 500, 1000, 2000, 5000])
    compare(settings.leftClick, "open")
  }

  function test_left_click_data() {
    return [
      { tag: "toggle", input: 'left_click = "toggle"', expected: "toggle" },
      { tag: "trailing comment", input: 'left_click = "toggle" # why', expected: "toggle" },
      { tag: "commented out", input: '# left_click = "toggle"', expected: "open" },
      { tag: "unknown value", input: 'left_click = "flip"', expected: "open" },
      { tag: "unquoted", input: 'left_click = toggle', expected: "open" },
      { tag: "hash inside string", input: 'left_click = "toggle"', expected: "toggle" },
      { tag: "missing", input: '', expected: "open" }
    ]
  }

  function test_left_click(data) {
    compare(Settings.parse(data.input).leftClick, data.expected)
  }

  function test_poll_intervals_data() {
    return [
      { tag: "single", input: "poll_intervals = [1000]", expected: [1000] },
      { tag: "trailing comma", input: "poll_intervals = [250, 500,]", expected: [250, 500] },
      { tag: "spaced", input: "poll_intervals=[ 250 ,500 ]", expected: [250, 500] },
      { tag: "empty list", input: "poll_intervals = []", expected: null },
      { tag: "non-integer", input: "poll_intervals = [250, fast]", expected: null },
      { tag: "not a list", input: "poll_intervals = 250", expected: null },
      { tag: "missing", input: "", expected: null }
    ]
  }

  function test_poll_intervals(data) {
    compare(Settings.parse(data.input).pollIntervals, data.expected)
  }

  function test_absent_file() {
    compare(Settings.parse(null).pollIntervals, null)
    compare(Settings.parse(null).leftClick, "open")
  }
}
