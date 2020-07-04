#!/usr/bin/env bash

declare -a job_list
declare -a categories
declare -a choices
declare -i job_id=0

progsfile="progs.csv"
script_dir="scripts"
LOGFILE=install.log
DEBUG=1


main() {
  while getopts "hfr:" o; do case "${o}" in
    h) printf "Optional arguments for custom use:\\n  -f: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit ;;
    f) progsfile=${OPTARG} ;;
  	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
  esac done

  log starting script
  sudo -v

  preprocess

  [ -r "${progsfile:?not set}" ] || { log -e cannot find $progsfile ; exit 1 ; }
  read_progs <(sort --field-separator=',' -r -k3 -k1 -k2 $progsfile)

  for choice in $choices ; do
    run_job "${job_list[$choice]}"
  done
}


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
  log running prerequisites
  prereq=(dialog curl git binutils make gcc pkg-config fakeroot)
  for pkg in ${prereq[@]} ; do
    install_pkg $pkg
  done

  if [ ! $(pacman -Qq yay 2>/dev/null) ] ; then
    install_git yay https://aur.archlinux.org/yay.git
  fi
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
      [[ "$cat" == "$category" ]] && options+=($id "$desc" on)
    done
    choices+=$(dialog --separate-output --checklist "$category" $((${#options[@]}/3+7)) 50 16 "${options[@]}" 2>&1 >/dev/tty)" "
  done
  clear
}


run_job() {
  IFS=',' read -r id tag cat name desc <<< "$@"
  case $tag in
    P) install_pkg $name ;;
    A) install_pkg -A $name ;;
    S) run_script $name ;;
  esac
}


install_pkg() {
  [ "$1" == "-A" ] && { aur=yay; shift; }
  if [ ! $(pacman -Qq $1 2>/dev/null) ] ; then
    log installing ${aur:+AUR} package "\e[1;96m$1\e[0m"
    catch sudo ${aur:-pacman} --noconfirm --needed -S "$1"
  else
    log package "\e[1;96m$1\e[0m" is already installed
  fi
}


install_git() {
  log installing package "\e[1;96m$1\e[0m"
  TEMP_DIR="$(mktemp -d)"
  git clone "$2" $TEMP_DIR >/dev/null 2>&1
  (cd $TEMP_DIR && catch makepkg -csi --noconfirm)
}


run_script() {
  log running script "\e[1;96m$1\e[0m"
  [ ! -f scripts/$1 ] && { log -e script file \'scripts/$1\' does not exist ; return ; }
  catch source "scripts/$1" 
}


log_setup
main $*