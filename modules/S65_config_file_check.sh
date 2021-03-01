#!/bin/bash

# emba - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2021 Siemens AG
# Copyright 2020-2021 Siemens Energy AG
#
# emba comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# emba is licensed under GPLv3
#
# Author(s): Michael Messner, Pascal Eckmann

# Description:  Scan for config files and check fstab
#               Access:
#                 firmware root path via $FIRMWARE_PATH
#                 binary array via ${BINARIES[@]}
export HTML_REPORT

S65_config_file_check()
{
  module_log_init "${FUNCNAME[0]}"
  module_title "Search/scan config files"

  scan_config
  check_fstab
  print_output "[*] $(date) - ${FUNCNAME[0]} finished ... " "main"
}

scan_config()
{
  sub_module_title "Search for config file"

  local CONF_FILES_ARR
  readarray -t CONF_FILES_ARR < <(config_find "$CONFIG_DIR""/config_files.cfg")

  if [[ "${CONF_FILES_ARR[0]}" == "C_N_F" ]] ; then print_output "[!] Config not found"
  elif [[ ${#CONF_FILES_ARR[@]} -ne 0 ]] ; then
    HTML_REPORT=1
    print_output "[+] Found ""${#CONF_FILES_ARR[@]}"" possible configuration files:"
    for LINE in "${CONF_FILES_ARR[@]}" ; do
      #if [[ -f "$LINE" ]] ; then
      print_output "$(indent "$(orange "$LINE")")" # "$(print_path "$LINE")"
      #fi
    done
  else
    print_output "[-] No configuration files found"
  fi
}

check_fstab()
{
  sub_module_title "Scan fstab"

  IFS=" " read -r -a FSTAB_ARR < <(printf '%s' "$(mod_path "/ETC_PATHS/fstab")")

  if [[ ${#FSTAB_ARR[@]} -ne 0 ]] ; then
    readarray -t FSTAB_USER_FILES < <(printf '%s' "$(find "${FSTAB_ARR[@]}" "${EXCL_FIND[@]}" -xdev -exec grep "username" {} \;)")
    readarray -t FSTAB_PASS_FILES < <(printf '%s' "$(find "${FSTAB_ARR[@]}" "${EXCL_FIND[@]}" -xdev -exec grep "password" {} \;)")
  fi

  if [[ ${#FSTAB_USER_FILES[@]} -gt 0 ]] ; then
    HTML_REPORT=1
    print_output "[+] Found ""${#FSTAB_USER_FILES[@]}"" fstab files with user details included:"
    for LINE in "${FSTAB_USER_FILES[@]}"; do
      print_output "$(indent "$(print_path "$LINE")")"
    done
    echo
  else
    print_output "[-] No fstab files with user details found"
  fi

  if [[ ${#FSTAB_PASS_FILES[@]} -gt 0 ]] ; then
    HTML_REPORT=1
    print_output "[+] Found ""${#FSTAB_PASS_FILES[@]}"" fstab files with password credentials included:"
    for LINE in "${FSTAB_PASS_FILES[@]}"; do
      print_output "$(indent "$(print_path "$LINE")")"
    done
    echo
  else
    print_output "[-] No fstab files with passwords found"
  fi

}
