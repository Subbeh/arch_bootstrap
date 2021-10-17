#!/usr/bin/env bash
#
# Arch based bootstrapping script
#
# PURPOSE: Automate the setup of a new Arch installation by installing
#          predefined packages and running configuration scripts.


## Environment variables
default_config="http://config.b00t.me"
LOGFILE=install.log
export DEBUG=1


## Main function
main() {
  if [ $(id -u) = 0 ] ; then
    whiptail \
      --title 'Error' \
      --msgbox "Please avoid running this as root" \
      10 40
    exit 1
  fi

  # cache password
  sudo -v
  
  preprocess
  sleep 2
  setup

  read_config $config

  for choice in $choices ; do
    run_job "${job_list[$choice]}"
  done
}


## Pre-processing - install build packages and AUR helper
preprocess() {
  log running prerequisites

  log refreshing package databases
  catch sudo pacman --noconfirm -Syy

  prereq=(dialog curl git binutils make gcc pkg-config fakeroot rsync)
  whiptail --title "Preprocess" \
           --yesno \
           --yes-button "Continue" \
           --no-button "Exit" \
           "The following required packages will be installed:\n\n$(printf ' • %s\n' "${prereq[@]}")" \
           0 0 3>&1 1>&2 2>&3 3>&1- || exit

  for pkg in ${prereq[@]} ; do
    install_pkg $pkg
  done

  if [ ! $(pacman -Qq yay 2>/dev/null) ] ; then
    install_git yay https://aur.archlinux.org/yay.git
  fi
}


## Setup configuration
setup() {
  while true ; do
    config_file=$(
      whiptail \
        --title "Config File" \
        --inputbox "\nPlease enter the config file location. This can be a local file or a hosted file (starting with http(s)://): " \
        0 78 ${1:-$default_config} \
        3>&1 1>&2 2>&3 3>&1-
    ) || exit

    if [[ "${config_file:=$default_config}" =~ ^https?:// ]] ; then
      config=$(mktemp)
      curl -sSfL "$config_file" > $config && break
    elif [ -f "$config_file" ] ; then
      config=$config_file
      break
    fi
    whiptail \
      --title 'Error' \
      --msgbox "Unable to access file/url:\n\n$config_file" \
      10 40
  done
}


## Process the configuration file
read_config() {
  [ -r "${1:?not set}" ] || { log -e cannot find $1 ; exit 1 ; }
  _dlg() { 
    choices+=$(
      dialog --keep-tite \
        --backtitle "Arch Bootstrap Installation Script" \
        --separate-output \
        --checklist \
        "$cat" \
        0 0 0 \
        "${options[@]}" \
        2>&1 >/dev/tty)" " || exit
  }

  while IFS=, read -r tag name cmd desc ; do
    [[ $tag == "=CMD" ]] && break;
    if [[ $tag =~ ^= ]] ; then
      [[ "$options" ]] && _dlg
      options=()
      cat=${tag/=/}
      continue
    fi

    [[ ! $tag =~ ^[PAC] ]] && continue
    job_list[$((++id))]=$id,$tag,$cat,$name,$desc,$cmd

    options+=($id "${desc:-$name}" ${checkbox:-off})
  done < $1

  # extract custom scripts
  scriptdir=$(mktemp -d)
  gawk -F'[: ]' -v sd="$scriptdir/" '
    match($0, /=CMD ([^:]*):(.*)/, a) { print a[2] > sd a[1] }
    /^=CMD/ { script=$2 ; next }
    /^=/ && script { script="" }
    script { print $0 > sd script ; next }
    ' $1

  [[ "$options" ]] && _dlg
  clear
}


## Run jobs based on tag
run_job() {
  IFS=',' read -r id tag cat name desc cmd <<< "$@"
  case $tag in
    P) install_pkg $name ;;
    A) install_pkg -A $name ;;
    C) cmd=${cmd:-$name} ;;
  esac

  [ "$cmd" ] && run_script $cmd
}


## Run Pacman/AUR helper
install_pkg() {
  [ "$1" == "-A" ] && { aur=yay ; shift ; }
    for pkg in "$@" ; do
    if [ ! $(pacman -Qq $pkg 2>/dev/null) ] ; then
      log installing ${aur:+AUR} package "\e[1;96m$pkg\e[0m"
      catch ${aur:-sudo pacman} --noconfirm --needed -S "$pkg"
    else
      log package "\e[1;96m$pkg\e[0m" is already installed
    fi
  done
}


## Install from git repository
install_git() {
  log installing package "\e[1;96m$1\e[0m"
  git_dir="$(mktemp -d)"
  git clone "$2" $git_dir >/dev/null 2>&1
  (cd $git_dir && catch makepkg -csi --noconfirm)
}


## Run custom script
run_script() {
  log running script "\e[1;96m$1\e[0m"
  [ ! -f "${scriptdir:?not set}/$1" ] && { log -e script \'$1\' is not defined ; return ; }
  catch source "${scriptdir:?not set}/$1"
}


## Script cleanup
cleanup() {
  sleep 1
  rm -rf $err $dbg $scriptdir $git_dir 2>/dev/null
  tput rmcup
  printf "FINISHED\nlogfile: %s\n" "$LOGFILE"
  kill $(jobs -p)
  exit
}


## Logging and error handling
log() {
  case $1 in
    -d) (($DEBUG)) || return ; l=DEBUG ; shift ;;
    -e) l=ERROR ; shift ;;
    -w) l=WARNING ; shift ;;
    *)  l=INFO ;;
  esac
  printf "[$(date --rfc-3339=seconds)] $l: "
  echo -e $*
}

> $LOGFILE
exec > >(tee -a $LOGFILE)
exec 2>&1

tput smcup
trap 'cleanup' 1 2 EXIT

export -f log
{ err="$(mktemp -u /tmp/err-pipe.XXX)" ; dbg="$(mktemp -u /tmp/dbg-pipe.XXX)"; } && mkfifo $err $dbg

cat <> $err 2>/dev/null | while IFS= read line ; do log -w $line ; done &
cat <> $dbg 2>/dev/null | while IFS= read line ; do log -d $line ; done &

catch() { $@ >>$dbg 2>>$err; }


## Run main function
declare -a job_list
declare -a categories
declare -a choices
declare -i id=0

main $*
