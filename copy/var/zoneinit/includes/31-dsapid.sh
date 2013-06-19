
log "creating /database directory and setting permissions"

if [[ ! -e /database ]]; then
  mkdir /database
fi

chown -R couchdb:couchdb /database

log "starting couchdb instance"

/usr/sbin/svcadm enable epmd:default
/usr/sbin/svcadm enable couchdb:default

log "waiting for couchdb"

COUCHDB_TIMEOUT=60
while [[ ! $(netstat -an | grep 127.0.0.1.5984) ]]; do
  : ${MYCOUNT:=0}
  sleep 1
  ((MYCOUNT=MYCOUNT+1))
  if [[ $MYCOUNT -eq $COUCHDB_TIMEOUT ]]; then
    log "ERROR Could not talk to CouchDB after ${COUCHDB_TIMEOUT} seconds"
    ERROR=yes
    break 1
  fi
done
[[ -n "${ERROR}" ]] && exit 31

log "(it took ${MYCOUNT} seconds to start properly)"

sleep 1

[[ "$(svcs -Ho state couchdb:default)" == "online" ]] || \
  ( log "ERROR CouchDB SMF not reporting as 'online'" && exit 31 )

log "adding ui"

DSAPI_INSTALL_UI=$(mdata-get dsapi_install_ui 2>/dev/null) || DSAPI_INSTALL_UI="false"

if [[ "${DSAPI_INSTALL_UI}" == "true" ]]; then
  /opt/local/gnu/bin/tar -xjf /var/zoneinit/dsapi-ui.tar.bz2 -C /opt/dsapi-ui
fi

log "adding default sync source"

DSAPI_SOURCE_NAME=$(mdata-get dsapi_source_name 2>/dev/null) || DSAPI_SOURCE_NAME="joyent"
DSAPI_SOURCE_URL=$(mdata-get dsapi_source_url 2>/dev/null) || DSAPI_SOURCE_URL="https://datasets.joyent.com/datasets"
DSAPI_SOURCE_TYPE=$(mdata-get dsapi_source_type 2>/dev/null) || DSAPI_SOURCE_TYPE="manifest"

if [[ "${DSAPI_SOURCE_TYPE}" == "manifest" ]]; then
  /opt/dsapi/bin/add-sync-source "${DSAPI_SOURCE_NAME}" "${DSAPI_SOURCE_URL}"
elif [[ "${DSAPI_SOURCE_TYPE}" == "deep" ]]; then
  /opt/dsapi/bin/add-sync-source "${DSAPI_SOURCE_NAME}" "${DSAPI_SOURCE_URL}" -f
fi

log "syncing manifests"

/opt/dsapi/sbin/dsapi-sync-manifests

log "adding dsapid instance"

svccfg import /opt/dsapi/smf/dsapid.xml

log "starting dsapid instance"

/usr/sbin/svcadm enable dsapid:default

log "starting nginx proxy"

/usr/sbin/svcadm enable nginx:default
