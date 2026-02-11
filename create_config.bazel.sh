#!/bin/bash
set -euo pipefail

output="${1}"

function write_define() {
  stamp_variable="${1}"
  default="${2}"
  variable=${stamp_variable#"STABLE_"}

  value=$( cat bazel-out/stable-status.txt | grep "${variable}" || true )

  if [[ "${value}" != "" ]]; then
    value=$(echo "${value}" | awk '{print $2}')
  else
    value="${default}"
  fi

  echo "#define ${variable} \"${value}\"" >> "${output}"
}

write_define "STABLE_SAIREDIS_GIT_REVISION" "ffffffff"
write_define "STABLE_SAI_GIT_REVISION" "ffffffff"
