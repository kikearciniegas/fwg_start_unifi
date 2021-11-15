#!/bin/bash

##
# script to make docker containers' configuration persist between reboots of the firewalla box
# the script must be created at /home/pi/.firewalla/config/post_main.d/start_[service-name].sh

##
# as per our own configuration, the docker root has been moved to the ssd drive
# so, after every reboot, we must check whether or not, the drive is mounted
# and the /var/lib/docker directory has been copied to the new docker root path
# before starting the docker containers

##
# args
SRVCNAME='unifi'
TMPDIR='/tmp'
MNTDIR='/mnt/data'
CHCK_FILE='/.do_not_remove_this_file'
LOG_FILE="/tmp/docker@$SRVCNAME.log"
DATADIR="$MNTDIR/docker/$SRVCNAME/data"
USRNAME='pi'
DCKRGROUP='docker'

##
# start unifi docker container
# 1. check for access to mount point
# 2. check for access to data dir
# 3. start docker daemon
# 4. spin up the docker container
# 5. add routing rules
# 6. add dnsmasq entry
# 5. end

##
# start the script
printf "%s\n" "script has started..."

##
# check for the ssd hdd mount point
#
printf "%b\n" "\naccessing $MNTDIR$CHCK_FILE..."
if [[ -f $MNTDIR$CHCK_FILE ]]; then
  printf "%s\n" " - $MNTDIR$CHCK_FILE is accessible... ok"
else
  printf "%s\n" " * - couldn't access $MNTDIR$CHCK_FILE... something is wrong"
  printf "%b\n" "$(date +%F) - couldn't access $MNTDIR$CHCK_FILE... something is wrong" >> $LOG_FILE
  printf "%s\n" " - let's run the move docker root script which also will call the ssd hdd mounting script anyways..."
  ./move_docker_root.sh
  sleep 5
  if [[ -f $MNTDIR$CHCK_FILE ]]; then
    printf "%s\n" " - $MNTDIR$CHCK_FILE is accessible... ok"
  else
    printf "%s\n" " * - couldn't access $MNTDIR$CHCK_FILE... something is wrong"
    printf "%b\n" "$(date +%F) - couldn't access $MNTDIR$CHCK_FILE... something is wrong" >> $LOG_FILE
    exit 1
  fi
fi

cd $TMPDIR
printf "%s\n" "moved to $(pwd)"

# check for access to the data dir
printf "%b\n" "\naccessing $DATADIR..."
if [[ -d $DATADIR ]]; then
  sudo chmod -R 775 $DATADIR && sudo chown -R $USRNAME:$DCKRGROUP $DATADIR
  printf "%s\n" " - $DATADIR is accessible, permissions applied and group ownership updated... ok"
else
  sudo mkdir -p $DATADIR && sudo chmod -R 775 $DATADIR && sudo chown -R $USRNAME:$DCKRGROUP $DATADIR
  printf "%s\n" " - $DATADIR has been created, permissions applied and group ownership updated... ok"
  printf "%s\n" " * - no docker-compose.yaml file has been found, exiting now..."
  exit 1
fi

# check if the docker daemon is running
#
printf "%b\n" "\nstarting the docker daemon..."
if (! sudo docker stats --no-stream ); then
  sudo systemctl start docker
  sleep 5
  #wait until docker daemon is running and has completed initialisation
  while (! sudo docker stats --no-stream ); do
    # docker takes a few seconds to initialize
    printf "%s\n" " - waiting for docker to launch..."
    sleep 5
  done
  sudo docker system prune -a -f --volumes
  printf "%s\n" " - docker daemon restarted... ok"
else
  sudo systemctl restart docker
  sleep 5
  printf "%s\n" " - docker daemon is running... ok"
fi

# start the docker container
#
sudo systemctl start docker-compose@$SRVCNAME

# add routing rules for docker network
#
sudo ipset create -! docker_lan_routable_net_set hash:net
sudo ipset add -! docker_lan_routable_net_set 172.16.1.0/24
sudo ipset create -! docker_wan_routable_net_set hash:net
sudo ipset add -! docker_wan_routable_net_set 172.16.1.0/24

# add local dnsmasq entry
#
sudo printf "%b\n" "address=/$SRVCNAME/172.16.1.2" > ~/.firewalla/config/dnsmasq_local/$SRVCNAME
# restart dns service
sudo systemctl restart firerouter_dns
# finished starting the docker container
printf "%b\n" "\nstart $SRVCNAME script has ended..."
##
