#!/usr/bin/env bash
#
# SCRIPT: bootstrap.sh
# AUTHOR: Steven Terwindt <info@sterwindt.com>
# DATE:   2020-07-05
# REV:    1.0
#
# PLATFORM: Arch based Linux distributions
#
# PURPOSE: Automate the setup of a new Arch installation by installing
#          predefined packages and running configuration scripts


## Variables
declare -a job_list
declare -a categories
declare -a choices
declare -i id=0

progsfile="progs.csv"
script_dir="scripts"
LOGFILE=install.log
export DEBUG=1
checkbox=on # toggle checkboxes on/off


## Logging and error handling
> $LOGFILE
exec > >(tee -a $LOGFILE)
exec 2>&1

tput smcup
trap 'tput rmcup || clear; exit 0' SIGINT EXIT

log() {
  case $1 in
    -d) [ ${DEBUG:-0} -ne 1 ] && return ; l=DEBUG ; shift ;;
    -e) l=ERROR ; shift ;;
    *)  l=INFO ;;
  esac
  printf "[$(date --rfc-3339=seconds)] $l: $*\n"
}

export -f log
err="$(mktemp)" ; dbg="$(mktemp)"
tail -f $err 2>/dev/null | while IFS= read line ; do log -e $line ; done &
tail -f $dbg 2>/dev/null | while IFS= read line ; do log -d $line ; done &

catch() { $@ >>$dbg 2>>$err; }


## Main function
main() {
  while getopts "hf:a:" o ; do case "${o}" in
    h) printf "Optional arguments for custom use:\\n  -f: Dependencies and programs csv\\n  -h: Show this message\\n" && exit ;;
    f) progsfile=${OPTARG} ;;
  	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
  esac done

  log starting script
  sudo -v

  preprocess
  sleep 2
  read_progs $progsfile

  for choice in $choices ; do
    run_job "${job_list[$choice]}"
  done
}


## Pre-processing - install build packages and AUR helper
preprocess() {
  log running prerequisites
  [ $(id -u) = 0 ] && { log -e script cannot be run as root ; exit 1 ; }

  prereq=(dialog curl git binutils make gcc pkg-config fakeroot)
  for pkg in ${prereq[@]} ; do
    install_pkg $pkg
  done

  if [ ! $(pacman -Qq yay 2>/dev/null) ] ; then
    install_git yay https://aur.archlinux.org/yay.git
  fi
}


## Read progs list and run configuration dialogs
read_progs() {
  [ -r "${1:?not set}" ] || { log -e cannot find $1 ; exit 1 ; }
  _dlg() { choices+=$(dialog --separate-output --checklist "$cat" $((${#options[@]}/3+7)) 50 16 "${options[@]}" 2>&1 >/dev/tty)" " ; }

  while IFS=, read -r tag name desc cmd ; do
    if [[ $tag =~ ^= ]] ; then
      [[ "$options" ]] && _dlg
      options=()
      cat=${tag/=/}
      continue
    fi

    [[ ! $tag =~ ^[SPA] ]] && continue
    job_list[$((++id))]=$id,$tag,$cat,$name,$desc,$cmd
    options+=($id "$desc" ${checkbox:-off})
  done < $1

  [[ "$options" ]] && _dlg
  clear
}


## Run jobs based on tag
run_job() {
  IFS=',' read -r id tag cat name desc cmd <<< "$@"
  case $tag in
    P) install_pkg $name ;;
    A) install_pkg -A $name ;;
    S) run_script $name ;;
  esac

  [ "$cmd" ] && catch $cmd
}


## Run Pacman/AUR helper
install_pkg() {
  [ "$1" == "-A" ] && { aur=yay ; shift ; }
  if [ ! $(pacman -Qq $1 2>/dev/null) ] ; then
    log installing ${aur:+AUR} package "\e[1;96m$1\e[0m"
    catch ${aur:-sudo pacman} --noconfirm --needed -S "$1"
  else
    log package "\e[1;96m$1\e[0m" is already installed
  fi
}


## Install from Git repository
install_git() {
  log installing package "\e[1;96m$1\e[0m"
  TEMP_DIR="$(mktemp -d)"
  git clone "$2" $TEMP_DIR >/dev/null 2>&1
  (cd $TEMP_DIR && catch makepkg -csi --noconfirm)
}


## Run custom script
run_script() {
  log running script "\e[1;96m$1\e[0m"
  [ ! -f scripts/$1 ] && { log -e script file \'scripts/$1\' does not exist ; return ; }
  catch source "scripts/$1" 
}


## Run main function
main $*