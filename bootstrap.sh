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
#          predefined packages and running configuration scripts.
#          Based on Luke Smith's LARB script here: https://larbs.xyz/
## Usage
usage="
Optional arguments for custom use:
  -f: Config file
  -h: Show this message\n
"

## Environment variables
default_config="config"
LOGFILE=install.log
export DEBUG=1


while getopts "hf:" o ; do case "${o}" in
  h) printf "$usage" && exit ;;
  f) user_defined_steps=${OPTARG} ;;
  *) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done


## Main function
main() {

  [ $(id -u) = 0 ] && { log -e script must not be run as root ; exit 1 ; }
  
  preprocess

  setup $user_defined_steps

  read_config $config

  for choice in $choices ; do
    run_job "${job_list[$choice]}"
  done
}


## Setup configuration
setup() {
  while : ; do
    config_file=$(
      whiptail \
        --title "Config File" \
        --inputbox "\nPlease enter the config file location. This can be a local file or a hosted file (starting with http://): " \
        10 78 ${1:-$default_config} \
        3>&1 1>&2 2>&3 3>&1-
    ) || exit

    if [[ "${config_file:=$default_config}" =~ ^https?:// ]] ; then
      config=$(mktemp)
      curl -sSf "$config_file" > $config;
      [ $? -eq 0 ] && break ;
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


# Process the configuration file
read_config() {
  [ -r "${1:?not set}" ] || { log -e cannot find $1 ; exit 1 ; }
  _dlg() { 
    choices+=$(
      dialog \
        --backtitle "Arch Bootstrap Installation Script" \
        --separate-output \
        --checklist \
        "$cat" \
        $((${#options[@]}/3+7)) 0 0 \
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

    options+=($id "$desc" ${checkbox:-off})
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


## Pre-processing - install build packages and AUR helper
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


## Run jobs based on tag
run_job() {
  IFS=',' read -r id tag cat name desc cmd <<< "$@"
  case $tag in
    P) install_pkg $name ;;
    A) install_pkg -A $name ;;
  esac

  [ "$cmd" ] && run_script $cmd
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


## Run custom script
run_script() {
  log running script "\e[1;96m$1\e[0m"
  [ ! -f "${scriptdir:?not set}/$1" ] && { log -e script \'$1\' is not defined ; return ; }
  catch source "${scriptdir:?not set}/$1"
}


## Logging and error handling
log() {
  case $1 in
    -d) [ ${DEBUG:-0} -ne 1 ] && return ; l=DEBUG ; shift ;;
    -e) l=ERROR ; shift ;;
    *)  l=INFO ;;
  esac
  printf "[$(date --rfc-3339=seconds)] $l: $*\n"
}

cleanup() {
  rm -rf $err $dbg $scriptdir 2>/dev/null
  tput rmcup || clear
  printf "logfile: %s\n" "$LOGFILE"
  kill $(jobs -p)
  exit
}

> $LOGFILE
exec > >(tee -a $LOGFILE)
exec 2>&1

tput smcup
trap 'cleanup' 1 2 EXIT

export -f log
err="$(mktemp)" ; dbg="$(mktemp)"

tail -f $err 2>/dev/null | while IFS= read line ; do log -e $line ; done &
tail -f $dbg 2>/dev/null | while IFS= read line ; do log -d $line ; done &

catch() { $@ >>$dbg 2>>$err; }


## Run main function
declare -a job_list
declare -a categories
declare -a choices
declare -i id=0

main $*