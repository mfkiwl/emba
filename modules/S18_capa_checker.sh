#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2024-2024 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
# SPDX-License-Identifier: GPL-3.0-only
#
# Author(s): Michael Messner

# Description:  This module uses capa (https://github.com/mandiant/capa) for detecting binary behavior
#               Currently capa only supports x86 architecture

S18_capa_checker() {
  module_log_init "${FUNCNAME[0]}"
  module_title "Analyse binary behavior with capa"
  pre_module_reporter "${FUNCNAME[0]}"

  if [[ ! -e "${EXT_DIR}"/capa ]]; then
    print_output "[-] Missing capa installation ... exit module"
    module_end_log "${FUNCNAME[0]}" 0
    return
  fi
  if [[ ${BINARY_EXTENDED} -ne 1 ]] ; then
    print_output "[-] ${FUNCNAME[0]} - BINARY_EXTENDED not set to 1. You can set it up via a scan-profile."
    module_end_log "${FUNCNAME[0]}" 0
    return
  fi
  if [[ "${FULL_TEST}" -ne 1 ]]; then
    # we only need to wait if we are not using the full_scan profile
    module_wait "S13_weak_func_check"
  fi
  if [[ -s "${CSV_DIR}"/s13_weak_func_check.csv ]]; then
    local BINARIES=()
    # usually binaries with strcpy or system calls are more interesting for further analysis
    # to keep analysis time low we only check these bins
    mapfile -t BINARIES < <(grep "strcpy\|system" "${CSV_DIR}"/s13_weak_func_check.csv | sort -k 3 -t ';' -n -r | awk '{print $1}' || true)
  fi

  local lBINARY=""
  local lBIN_TO_CHECK=""
  local lWAIT_PIDS_S18=()
  local lBIN_TO_CHECK_ARR=()
  export BINS_CHECKED_ARR=()

  for lBINARY in "${BINARIES[@]}"; do
    mapfile -t lBIN_TO_CHECK_ARR < <(find "${LOG_DIR}/firmware" -name "$(basename "${lBINARY}")" | sort -u || true)
    for lBIN_TO_CHECK in "${lBIN_TO_CHECK_ARR[@]}"; do
      if [[ -f "${BASE_LINUX_FILES}" && "${FULL_TEST}" -eq 0 ]]; then
        # if we have the base linux config file we only test non known Linux binaries
        # with this we do not waste too much time on open source Linux stuff
        lNAME=$(basename "${lBIN_TO_CHECK}" 2> /dev/null)
        if grep -E -q "^${lNAME}$" "${BASE_LINUX_FILES}" 2>/dev/null; then
          continue 2
        fi
      fi

      if ( file "${lBIN_TO_CHECK}" | grep -q "ELF.*Intel" ); then
        # ensure we have not tested this binary entry
        local lBIN_MD5=""
        lBIN_MD5="$(md5sum "${lBIN_TO_CHECK}" | awk '{print $1}')"
        if [[ "${BINS_CHECKED_ARR[*]}" == *"${lBIN_MD5}"* ]]; then
          # print_output "[*] ${ORANGE}${lBIN_TO_CHECK}${NC} already tested with ghidra/semgrep" "no_log"
          continue
        fi

        if [[ "${THREADED}" -eq 1 ]]; then
          capa_runner_fct "${lBIN_TO_CHECK}" &
          local lTMP_PID="$!"
          store_kill_pids "${lTMP_PID}"
          lWAIT_PIDS_S18+=( "${lTMP_PID}" )
          max_pids_protection "${MAX_MOD_THREADS}" "${lWAIT_PIDS_S18[@]}"
        else
          capa_runner_fct "${lBIN_TO_CHECK}"
        fi

        # in normal operation we stop checking after the first 20 binaries
        # if FULL_TEST is activated we are testing all binaries -> this takes a long time
        if [[ "${#BINS_CHECKED_ARR[@]}" -gt 20 ]] && [[ "${FULL_TEST}" -ne 1 ]]; then
          print_output "[*] 20 binaries already analysed - ending capa binary analysis now." "no_log"
          print_output "[*] For complete analysis enable FULL_TEST." "no_log"
          break 2
        fi
      else
        print_output "[-] Binary behavior testing with capa for $(print_path "${lBIN_TO_CHECK}") not possible ... unsupported architecture"
      fi
    done
  done

  [[ "${THREADED}" -eq 1 ]] && wait_for_pid "${lWAIT_PIDS_S18[@]}"

  print_ln
  print_output "[*] Found ${ORANGE}${#BINS_CHECKED_ARR[@]}${NC} capa results in ${ORANGE}${#BINARIES[@]}${NC} binaries"

  module_end_log "${FUNCNAME[0]}" "${#BINS_CHECKED_ARR[@]}"
}

capa_runner_fct() {
  local lBINARY="${1:-}"

  local lBIN_NAME=""
  lBIN_NAME="$(basename "${lBINARY}")"

  print_output "[*] Testing binary behavior with capa for $(print_path "${lBINARY}")" "no_log"
  "${EXT_DIR}"/capa "${lBINARY}" > "${LOG_PATH_MODULE}/capa_${lBIN_NAME}".log || print_output "[-] Capa analysis failed for ${lBINARY}" "no_log"

  if [[ -s "${LOG_PATH_MODULE}/capa_${lBIN_NAME}.log" ]]; then
    print_output "[+] Capa results for ${ORANGE}$(print_path "${lBINARY}")${NC}" "" "${LOG_PATH_MODULE}/capa_${lBIN_NAME}.log"
    local lBIN_MD5=""
    lBIN_MD5="$(md5sum "${lBIN_TO_CHECK}" | awk '{print $1}')"
    BINS_CHECKED_ARR+=( "${lBIN_MD5}" )
  else
    print_output "[*] No capa results for $(print_path "${lBINARY}")" "no_log"
    rm "${LOG_PATH_MODULE}/capa_${lBIN_NAME}.log" || true
  fi
}
