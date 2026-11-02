# Add a repository stanza ahead of the existing ones (after [options]) so its
# packages win over namesakes, replacing any previous stanza with that name.
# Usage: awk -v name=omarchy -v server=URL -v siglevel='Required DatabaseOptional' -f pacman-config.awk pacman.conf
# Based on omarchy-on-cachyos (MIT, Mark Roboff and MiguelU-coder).
function stanza() {
  print "[" name "]"
  print "SigLevel = " siglevel
  print "Server = " server
  print ""
  added=1
}
/^[[:space:]]*\[[^]]+\]/ {
  header=$0
  sub(/^[[:space:]]*\[/, "", header)
  sub(/\].*/, "", header)
  skip=(header == name)
  if (header != "options" && !added) stanza()
}
!skip { print }
END { if (!added) stanza() }
