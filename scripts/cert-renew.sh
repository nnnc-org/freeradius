#!/bin/bash

#exit 0

FREERADIUS_FULLCHAIN="/etc/raddb/certs/fullchain.pem"
FREERADIUS_KEY="/etc/raddb/certs/server.key"

print_header() {
    echo "--------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------"
}

renew_cert() {
    print_header "Renewing certificate for $CERT_DOMAIN"
    cd /acme
    . /acme/acme.sh.env
    ./acme.sh --renew -d $CERT_DOMAIN \
              --config-home /acme/data \
              --home /acme \
              --cert-home /acme/certs \
              --fullchain-file $FREERADIUS_FULLCHAIN \
              --key-file $FREERADIUS_KEY
}

fix_permissions() {
    print_header "Fixing Cert Permissions"
    chown -R root:freerad $FREERADIUS_FULLCHAIN $FREERADIUS_KEY
    chmod 640 $FREERADIUS_FULLCHAIN $FREERADIUS_KEY
}

compare_cert() {
    print_header "Comparing certificates"
    if [ "$CERT_FULLCHAINFILE_PATH" && "CERT_KEYFILE_PATH" ]; then
        if [ ! -f $FREERADIUS_FULLCHAIN ] || [ ! -f $FREERADIUS_KEY ]; then
            print_header "Installing certificate for $CERT_DOMAIN"
            cp $CERT_FULLCHAINFILE_PATH $FREERADIUS_FULLCHAIN
            cp $CERT_KEYFILE_PATH $FREERADIUS_KEY
        else
            if ! cmp -s $CERT_FULLCHAINFILE_PATH $FREERADIUS_FULLCHAIN || ! cmp -s $CERT_KEYFILE_PATH $FREERADIUS_KEY; then
                print_header "Certificates are different, installing new ones"
                cp $CERT_FULLCHAINFILE_PATH $FREERADIUS_FULLCHAIN
                cp $CERT_KEYFILE_PATH $FREERADIUS_KEY
            fi
        fi
    fi
}

restart_freeradius() {
    # check if cert files have been updated recently (within last 12 hours) using stat
    # if so, restart FreeRADIUS
    if [ $(stat -c %Y $FREERADIUS_FULLCHAIN) -gt $(date -d '12 hours ago' +%s) ] || [ $(stat -c %Y $FREERADIUS_KEY) -gt $(date -d '12 hours ago' +%s) ]; then
        print_header "Certificates have been updated, restarting FreeRADIUS"
        supervisorctl restart all:freeradius
    fi
}

## If LE_EMAIL is set, we will use Let's Encrypt to renew the certificate
if [ "$CERT_DOMAIN" ] && [ "$LE_EMAIL" ]; then
    renew_cert
    fix_permissions
elif [ "$CERT_FULLCHAINFILE_PATH" ] && [ "$CERT_KEYFILE_PATH" ]; then
    compare_cert
    fix_permissions
else
    echo "No certificate to renew or install"
fi

restart_freeradius
