import QtQuick
import QtTest
import "../lib/BtopHumanizer.js" as BtopHumanizer

TestCase {
  name: "BtopHumanizer"

  function test_floating_humanizer_data() {
    return [
      { tag: "zero", input: 0, expected: "0B" },
      { tag: "bytes", input: 512, expected: "512B" },
      { tag: "kib", input: 1024, expected: "1.0K" },
      { tag: "mib", input: 1048576, expected: "1.0M" },
      { tag: "512m", input: 536870912, expected: "512M" },
      { tag: "1.5g", input: 1610612736, expected: "1.5G" },
      { tag: "4g", input: 4294967296, expected: "4.0G" },
      { tag: "8g", input: 8589934592, expected: "8.0G" },
      { tag: "24g", input: 25769803776, expected: "24G" }
    ]
  }

  function test_floating_humanizer(data) {
    compare(BtopHumanizer.floatingHumanizer(data.input), data.expected)
  }

  function test_vram_text_data() {
    return [
      {
        tag: "btop screenshot",
        used: 1610612736,
        total: 4294967296,
        expected: "1.5G/4.0G (vRAM)"
      },
      { tag: "missing used", used: -1, total: 4294967296, expected: "-- (vRAM)" },
      { tag: "missing total", used: 0, total: -1, expected: "-- (vRAM)" },
      { tag: "zero total", used: 0, total: 0, expected: "-- (vRAM)" }
    ]
  }

  function test_vram_text(data) {
    compare(BtopHumanizer.vramText(data.used, data.total), data.expected)
  }
}
