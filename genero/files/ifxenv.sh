#!/bin/bash

export INFORMIXDIR=/opt/ibm
export INFORMIXSERVER=informix
export INFORMIXSQLHOSTS=$INFORMIXDIR/etc/sqlhosts
export PATH="${PATH}:$INFORMIXDIR/bin"

