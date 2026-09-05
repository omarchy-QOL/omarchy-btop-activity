function emit(    engine) {
  if (!(device in allowed) || client == "") return
  for (engine in engines)
    print "counter", device, client, engine,
      ns[engine] == "" ? "-" : ns[engine],
      cycles[engine] == "" ? "-" : cycles[engine],
      total[engine] == "" ? "-" : total[engine],
      capacity[engine] == "" ? 1 : capacity[engine],
      frequency[engine] == "" ? "-" : frequency[engine]
}

BEGIN {
  OFS = "\t"
  count = split(wanted, ids, " ")
  for (i = 1; i <= count; i++) allowed[ids[i]] = 1
}
/^begin\t/ { started = $2; next }
/^end\t/ { ended = $2; next }
{
  separator = index($0, ":")
  file = substr($0, 1, separator - 1)
  line = substr($0, separator + 1)
  if (file != previous_file) {
    emit()
    delete ns; delete cycles; delete total; delete capacity
    delete frequency; delete engines
    client = device = ""
    previous_file = file
  }
  separator = index(line, ":")
  label = substr(line, 1, separator - 1)
  line = substr(line, separator + 1)
  sub(/^[[:space:]]+/, "", line)
  split(line, value, /[[:space:]]+/)
  if (label == "drm-client-id") client = value[1]
  else if (label == "drm-pdev") device = tolower(value[1])
  else if (value[1] ~ /^[0-9]+$/) {
    engine = label
    if (sub(/^drm-engine-capacity-/, "", engine))
      capacity[engine] = value[1]
    else if (sub(/^drm-engine-/, "", engine) && value[2] == "ns")
      ns[engine] = value[1]
    else if (sub(/^drm-total-cycles-/, "", engine))
      total[engine] = value[1]
    else if (sub(/^drm-cycles-/, "", engine))
      cycles[engine] = value[1]
    else if (sub(/^drm-maxfreq-/, "", engine)) {
      frequency[engine] = value[1]
      if (value[2] == "MHz") frequency[engine] *= 1000000
      if (value[2] == "KHz") frequency[engine] *= 1000
    }
    else next
    engines[engine] = 1
  }
}
END {
  emit()
  if (started > 0 && ended >= started)
    printf "time\t%.6f\n", (started + ended) / 2
}
