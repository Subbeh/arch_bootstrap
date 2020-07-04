#!/usr/bin/env bash

declare -a job_list
declare -a categories
declare -a choices
declare -i job_id=0

progsfile="progs.csv"
script_dir="scripts"
LOGFILE=install.log
DEBUG=1


log_setup() {
  exec > >(tee -a $LOGFILE)
  exec 2>&1
}


log() {
  case $1 in
    -d) [ $DEBUG -ne 1 ] && return ; l=DEBUG; shift ;;
    -e) l=ERROR; shift ;;
    *)  l=INFO ;;
  esac
  printf "[$(date --rfc-3339=seconds)] $l: $*\n"
}


catch() {
  err="$(mktemp)" ; dbg="$(mktemp)"
  $@ >$dbg 2>$err
  while read errmsg ; do log -e ${errmsg/error: /} ; done < $err
  while read dbgmsg ; do log -d $dbgmsg ; done < $dbg
}


preprocess() {
  [ ! $(command -v dialog) ] && install_pkg dialog
  [ ! $(command -v yay) ] && install_pkg yay
}

read_progs() {
  while IFS=, read -r tag cat name desc ; do
    [[ ! $tag =~ [SP] ]] && continue
    id=$((job_id++))
    job_list[$id]=$id,$tag,$cat,$name,$desc
    [[ ! " ${categories[@]} " =~ " ${cat} " ]] && categories+=($cat)
  done < $1

  for category in "${categories[@]}" ; do
    options=()
    for job in "${job_list[@]}" ; do
      IFS=',' read -r id tag cat name desc <<< "$job"
      [[ "$cat" == "$category" ]] && options+=($id "$name "$'\t'" $desc" on)
    done
    choices+=$(dialog --separate-output --checklist "$category" $((${#options[@]}/3+7)) 50 16 "${options[@]}" 2>&1 >/dev/tty)" "
  done
  clear
}


run_job() {
  IFS=',' read -r id tag cat name desc <<< "$@"
  case $tag in
    P) install_pkg $name ;;
    A) install_pkg_aur $name ;;
    S) run_script $name ;;
  esac
}


install_pkg() {
  log installing package "\e[1;96m$1\e[0m"
  catch sudo pacman --noconfirm --needed -S "$1"
}

install_pkg_aur() {
  log installing AUR package "\e[1;96m$1\e[0m"
  catch sudo yay --noconfirm --needed -S "$1"
}

run_script() {
  log running script "\e[1;96m$1\e[0m"
  catch source "scripts/$1" 
}

main() {
  while getopts "hfr:" o; do case "${o}" in
	  h) printf "Optional arguments for custom use:\\n  -f: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit ;;
	  f) progsfile=${OPTARG} ;;
  	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
  esac done

  log starting script
  sudo -v

  preprocess

  [ -r "${progsfile:?not set}" ] || { log -e cannot find $progsfile ; exit 1; }
  read_progs <(sort --field-separator=',' -r -k3 -k1 -k2 $progsfile)

  for choice in $choices ; do
    run_job "${job_list[$choice]}"
  done

}


log_setup
main $*
