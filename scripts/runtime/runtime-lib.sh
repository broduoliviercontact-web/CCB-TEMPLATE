#!/bin/sh
runtime_model_is_safe() { case "$1" in ''|*[!A-Za-z0-9._:/-]*) return 1;; *) return 0;; esac; }
runtime_warn() { printf '%s\n' "[WARN] $1" >&2; }

runtime_ollama_request_file() {
  model=$1; prompt=$2; output=$3
  awk -v model="$model" 'BEGIN { printf "{\"model\":\"%s\",\"prompt\":\"", model }
    { line=$0; gsub(/\\/, "\\\\", line); gsub(/\"/, "\\\"", line); gsub(/\r/, "\\r", line); gsub(/\t/, "\\t", line); printf "%s\\n", line }
    END { print "\",\"stream\":false}" }' "$prompt" >"$output"
}

runtime_ollama_extract_response() {
  input=$1; output=$2
  awk 'function hex_digit(c) { c=tolower(c); return index("0123456789abcdef",c)-1 }
    function unicode(hex, n,a,b,c) { n=hex_digit(substr(hex,1,1))*4096+hex_digit(substr(hex,2,1))*256+hex_digit(substr(hex,3,1))*16+hex_digit(substr(hex,4,1)); if (n<0) return ""; if (n<128) return sprintf("%c",n); if (n<2048) { a=192+int(n/64); b=128+(n%64); return sprintf("%c%c",a,b) } if (n<55296 || n>57343) { a=224+int(n/4096); b=128+int((n%4096)/64); c=128+(n%64); return sprintf("%c%c%c",a,b,c) } return "\\u" hex }
    BEGIN { ORS="" }
    { data = data $0 "\n" }
    END {
      if (substr(data,1,1) != "{" || index(data,"\"response\"") == 0) exit 1
      rest=substr(data,index(data,"\"response\"")+10)
      colon=index(rest,":"); if (!colon) exit 1
      rest=substr(rest,colon+1); sub(/^[[:space:]]*/,"",rest)
      if (substr(rest,1,1) != "\"") exit 1
      rest=substr(rest,2); escaped=0; closed=0
      for (i=1;i<=length(rest);i++) {
        c=substr(rest,i,1)
        if (escaped) {
          if (c=="n") printf "\n"; else if (c=="r") printf "\r"; else if (c=="t") printf "\t"; else if (c=="\"") printf "\""; else if (c=="\\") printf "\\"; else if (c=="b" || c=="f") printf " "; else if (c=="u") { hex=substr(rest,i+1,4); decoded=unicode(hex); if (decoded=="") exit 1; printf "%s",decoded; i+=4 } else exit 1
          escaped=0
        } else if (c=="\\") escaped=1
        else if (c=="\"") { closed=1; break }
        else printf "%s",c
      }
      if (!closed || escaped) exit 1
    }' "$input" >"$output"
}
