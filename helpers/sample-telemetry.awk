# Reuse cached paths; no device discovery or sampling sleep on the hot path.
function read_number(path, line, result) {
  result = (path != "" && (getline line < path) > 0 &&
    line ~ /^-?[0-9]+([.][0-9]+)?$/) ? line + 0 : "-"
  close(path)
  return result
}

function temperature(path, fault, result) {
  fault = path
  if (sub(/_input$/, "_fault", fault) && read_number(fault) == 1)
    return "-"
  result = read_number(path)
  return result == "-" ? "-" : result / 1000
}

BEGIN {
  OFS = "\t"
  if (mode != "sensors") {
    if (proc_root == "") proc_root = "/proc"
    if ((getline line < (proc_root "/stat")) > 0) {
      split(line, cpu, /[[:space:]]+/)
      if (cpu[1] == "cpu") {
        total = 0
        # guest time is already included in user and nice.
        for (i = 2; i <= 9; i++) total += cpu[i]
        busy = cpu[2] + cpu[3] + cpu[4] + cpu[7] + cpu[8]
        printf "cpu\t%.0f\t%.0f\n", busy, total
      }
    }
    while ((getline line < (proc_root "/meminfo")) > 0) {
      split(line, memory, /[[:space:]]+/)
      if (memory[1] == "MemTotal:") memory_total = memory[2] + 0
      if (memory[1] == "MemAvailable:") {
        memory_available = memory[2] + 0
        have_available = 1
      }
    }
    if (memory_total > 0 && have_available &&
        memory_available >= 0 && memory_available <= memory_total)
      printf "memory\t%.0f\t%.0f\n",
        (memory_total - memory_available) * 1024, memory_total * 1024
    exit
  }

  count = split(inventory, records, "\n")
  for (i = 1; i <= count; i++) {
    split(records[i], fields, "\t")
    if (fields[1] == "cpu")
      print "temperature", fields[2], temperature(fields[3])
    if (fields[1] != "gpu") continue
    state_path = fields[6] "/power/runtime_status"
    state = ""
    getline state < state_path
    close(state_path)
    if (state != "" && state != "active" && state != "unsupported") {
      print "gpu", fields[2], "sleeping", "-", "-", "-", "-"
      continue
    }
    print "gpu", fields[2], "active", read_number(fields[8]),
      temperature(fields[7]), read_number(fields[9]), read_number(fields[10])
  }
}
