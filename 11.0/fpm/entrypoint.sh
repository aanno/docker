#!/bin/bash
set -e

export BASE="/var/www/html"
if [ -n $BASE_PATH ]; then
    export BASE="${BASE}${BASE_PATH}"
fi
mkdir -p "${BASE}"

# version_greater A B returns whether A > B
function version_greater() {
	[[ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ]];
}

# return true if specified directory is empty
function directory_empty() {
    [ -n "$(find "$1"/ -prune -empty)" ]
}

function run_as() {
  if [[ $EUID -eq 0 ]]; then
    su - www-data -s /bin/bash -c "$1"
# su - www-data -s /bin/bash <<EOSU
# $1
# EOSU
  else
    bash -c "$1"
  fi
}

installed_version="0.0.0~unknown"
if [ -f ${BASE}/version.php ]; then
    installed_version=$(php -r 'require "'${BASE}'/version.php"; echo "$OC_VersionString";')
fi
image_version=$(php -r 'require "/usr/src/nextcloud/version.php"; echo "$OC_VersionString";')

if version_greater "$installed_version" "$image_version"; then
    echo "Can't start Nextcloud because the version of the data ($installed_version) is higher than the docker image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
    exit 1
fi

if version_greater "$image_version" "$installed_version"; then
    if [ "$installed_version" != "0.0.0~unknown" ]; then
        run_as 'php '${BASE}'/occ app:list' > /tmp/list_before
    fi
    if [[ $EUID -eq 0 ]]; then
      rsync_options="-rlDog --chown www-data:root"
    else
      rsync_options="-rlD"
    fi
    rsync $rsync_options --delete --exclude /config/ --exclude /data/ --exclude /custom_apps/ --exclude /themes/ /usr/src/nextcloud/ "$BASE"

    for dir in config data custom_apps themes; do
        if [ ! -d ${BASE}/"$dir" ] || directory_empty ${BASE}/"$dir"; then
            rsync $rsync_options --include /"$dir"/ --exclude '/*' /usr/src/nextcloud/ "$BASE"
        fi
    done

    echo "Base is ${BASE} - it can not be changed after the first startup"

    if [ "$installed_version" != "0.0.0~unknown" ]; then
        run_as 'php '${BASE}'/occ upgrade --no-app-disable'

        run_as 'php '${BASE}'/occ app:list' > /tmp/list_after
        echo "The following apps have beed disabled:"
        diff <(sed -n "/Enabled:/,/Disabled:/p" /tmp/list_before) <(sed -n "/Enabled:/,/Disabled:/p" /tmp/list_after) | grep '<' | cut -d- -f2 | cut -d: -f1
        rm -f /tmp/list_before /tmp/list_after
    fi
fi

exec "$@"
