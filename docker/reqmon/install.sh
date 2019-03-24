#!/bin/bash

ARCH=slc7_amd64_gcc630
VER=HG1902f
REPO="comp"
AREA=/data/cfg/admin
PKGS="admin backend reqmon"
SERVER=cmsrep.cern.ch

cd $WDIR
git clone git://github.com/dmwm/deployment.git cfg
mkdir $WDIR/srv

cd $WDIR/cfg
git reset --hard $VER

# adjust deploy script
sed -i -e "s,https://cmsweb.cern.ch,https://cmsweb-test.web.cern.ch,g" \
    -e "s,https://cmsweb-testbed.cern.ch,https://cmsweb-test.web.cern.ch,g" \
    -e "s,https://cmsweb-dev.cern.ch,https://cmsweb-test.web.cern.ch,g" \
    -e "s,https://\`hostname -f\`,https://cmsweb-test.web.cern.ch,g" \
    -e "s,dbs_ins=\"int\",dbs_inst=\"prod\",g" \
    -e "s,dbs_ins=\"dev\",dbs_inst=\"prod\",g" \
    -e "s,dbs_ins=\"private_vm\",dbs_inst=\"prod\",g" \
    reqmon/deploy

# Deploy services
# we do not use InstallDev script directly since we want to capture the status of
# install step script. Therefore we call Deploy script and capture its status every step
cd $WDIR
curl -sO http://cmsrep.cern.ch/cmssw/repos/bootstrap.sh
sh -x ./bootstrap.sh -architecture $ARCH -path $WDIR/tmp/$VER/sw -repository $REPO -server $SERVER setup
# deploy services
$WDIR/cfg/Deploy -A $ARCH -R comp@$VER -r comp=$REPO -t $VER -w $SERVER -s prep $WDIR/srv "$PKGS"
if [ $? -ne 0 ]; then
    cat $WDIR/srv/.deploy/*-prep.log
    exit 1
fi
$WDIR/cfg/Deploy -A $ARCH -R comp@$VER -r comp=$REPO -t $VER -w $SERVER -s sw $WDIR/srv "$PKGS"
if [ $? -ne 0 ]; then
    cat $WDIR/srv/.deploy/*-sw.log
    exit 1
fi
$WDIR/cfg/Deploy -A $ARCH -R comp@$VER -r comp=$REPO -t $VER -w $SERVER -s post $WDIR/srv "$PKGS"
if [ $? -ne 0 ]; then
    cat $WDIR/srv/.deploy/*-post.log
    exit 1
fi

# NOTE: we separated workqueue, reqmon, reqmgr2 and couchdb into individual
# containers. In k8s cluster we need to remove monitoring of services which are
# not part of the container/pod. The action items below perform that.

# remove monitoring configs for services which are not run in this container
for srv in "workqueue" "reqmgr2" "couchdb"; do
    fname=/data/srv/current/config/$srv/monitoring.ini
    if [ -f $fname ]; then
        rm $fname
    fi
done

# Adjust ServerMonitor to be specific
sed -i -e "s#ServerMonitor/2.0#ServerMonitor-reqmon#g" /data/srv/current/config/admin/ServerMonitor

# add proxy generation via robot certificate
crontab -l | egrep -v "reqmgr2|workqueue|couchdb|reboot" > /tmp/mycron
echo "3 */3 * * * sudo /data/proxy.sh $USER 2>&1 1>& /dev/null" >> /tmp/mycron
crontab /tmp/mycron
rm /tmp/mycron
