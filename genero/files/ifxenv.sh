#!/bin/bash

export INFORMIXDIR=/opt/ibm
export INFORMIXSERVER=informix
export INFORMIXSQLHOSTS=$INFORMIXDIR/etc/sqlhosts
export PATH="${PATH}:$INFORMIXDIR/bin"

export LD_LIBRARY_PATH=${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${INFORMIXDIR}/lib/tools:${INFORMIXDIR}/lib/cli:${LD_LIBRARY_PATH}
