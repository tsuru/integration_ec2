#!/bin/bash

set -e

TSURUVERSION=${TSURUVERSION:-latest}

echo "Going to test tsuru image version: $TSURUVERSION"

function abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
mypath=$(abspath $(dirname ${BASH_SOURCE[0]}))
finalconfigpath=$(mktemp)
installname=$(uuidgen | head -c 18)
cp ${mypath}/config.yml ${finalconfigpath}
sed -i.bak "s|\$AWSKEY|${AWSKEY}|g" ${finalconfigpath}
sed -i.bak "s|\$AWSSECRET|${AWSSECRET}|g" ${finalconfigpath}
sed -i.bak "s|\$INSTALLNAME|int-${installname}|g" ${finalconfigpath}
sed -i.bak "s|\$TSURUVERSION|${TSURUVERSION}|g" ${finalconfigpath}

tmpdir=$(mktemp -d)
export GOPATH=${tmpdir}
export PATH=$GOPATH/bin:$PATH
echo "Go get platforms..."
go get github.com/tsuru/platforms/...
echo "Go get tsuru..."
go get github.com/tsuru/tsuru/integration
echo "Go get tsuru client..."
go get github.com/tsuru/tsuru-client/...

export TSURU_INTEGRATION_examplesdir="${GOPATH}/src/github.com/tsuru/platforms/examples"
export TSURU_INTEGRATION_installerconfig=${finalconfigpath}
export TSURU_INTEGRATION_nodeopts="iaas=dockermachine"
export TSURU_INTEGRATION_maxconcurrency=4
export TSURU_INTEGRATION_verbose=1
export TSURU_INTEGRATION_enabled=1

go test -v -timeout 120m github.com/tsuru/tsuru/integration

rm -f ${finalconfigpath}
rm -f ${userdatapath}
