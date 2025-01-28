#!/bin/bash

set -e

[ "$DEBUG" ] && set -x

echo "$@"

# func to print header
print_header() {
    echo "--------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------"
}

setup_kerberos_pam() {
    print_header "Setting up Kerberos realm: \"${AD_DOMAIN^^}\""
    cat > /etc/krb5.conf << EOL
[logging]
    default = FILE:/var/log/krb5.log 
    kdc = FILE:/var/log/kdc.log 
    admin_server = FILE:/var/log/kadmind.log
[libdefaults]
    default_realm = ${AD_DOMAIN^^}
    dns_lookup_realm = false
    dns_lookup_kdc = false
[realms]
    ${AD_DOMAIN^^} = {
        kdc = $(echo ${AD_SERVER,,} | awk '{print $1}')
        admin_server = $(echo ${AD_SERVER,,} | awk '{print $1}')
        default_domain = ${AD_DOMAIN^^}       
    }
    ${AD_DOMAIN,,} = {
        kdc = $(echo ${AD_SERVER,,} | awk '{print $1}')
        admin_server = $(echo ${AD_SERVER,,} | awk '{print $1}')
        default_domain = ${AD_DOMAIN,,}
    }
    ${AD_WORKGROUP^^} = {
        kdc = $(echo ${AD_SERVER,,} | awk '{print $1}')
        admin_server = $(echo ${AD_SERVER,,} | awk '{print $1}')
        default_domain = ${AD_DOMAIN^^}       
    }
    
[domain_realm]
    .${AD_DOMAIN,,} = ${AD_DOMAIN^^}
    ${AD_DOMAIN,,} = ${AD_DOMAIN^^}
EOL
    echo "auth            sufficient      pam_krb5.so minimum_uid=1000" > /etc/pam.d/radiusd 
    echo "session         required        pam_krb5.so minimum_uid=1000" >> /etc/pam.d/radiusd
    echo "account         required        pam_krb5.so minimum_uid=1000" >> /etc/pam.d/radiusd
    echo "password        sufficient      pam_krb5.so minimum_uid=1000" >> /etc/pam.d/radiusd
}

# if ad_domain is set, then setup kerberos
if [ "$AD_DOMAIN" ]; then
    # Check for required AD Params
    [ -z "$AD_SERVER" ] && echo "AD_SERVER env variable not defined! Exiting..." && exit 1
    [ -z "$AD_WORKGROUP" ] && echo "AD_WORKGROUP env variable not defined! Exiting..." && exit 1
    #[ -z "$AD_USERNAME" ] && echo "AD_USERNAME env variable not defined! Exiting..." && exit 1
    #[ -z "$AD_PASSWORD" ] && echo "AD_PASSWORD env variable not defined! Exiting..." && exit 1
    export AD_HOSTNAME=$(hostname)

    setup_kerberos_pam
fi

# client setup (optional)
# loop through all env vars starting with RAD_CLIENT_
for var in "${!RAD_CLIENT_@}"; do
    declare -n ref=$var
    
    # only if var does not contain ADDR or SECRET, and ref is not empty
    if [[ ! $var == *_ADDR ]] && [[ ! $var == *_SECRET ]] && [ ! -z "$ref" ]; then
        print_header "Setup FreeRADIUS: Appending '$ref' to clients.conf"
        declare -n ref_ADDR=${var}_ADDR
        declare -n ref_SECRET=${var}_SECRET

        echo -e "\nclient $ref {" >> /etc/freeradius/clients.conf
        echo "    ipaddr = $ref_ADDR" >> /etc/freeradius/clients.conf
        echo "    secret = $ref_SECRET" >> /etc/freeradius/clients.conf
        echo "}" >> /etc/freeradius/clients.conf
    fi
done

# eduroam client setup
for var in "${!EDUROAM_CLIENT_@}"; do
    declare -n ref=$var
    
    # only if var does not contain ADDR or SECRET, and ref is not empty
    if [[ ! $var == *_ADDR ]] && [[ ! $var == *_SECRET ]] && [ ! -z "$ref" ]; then
        print_header "Setup FreeRADIUS: Appending '$ref' to clients.conf"
        declare -n ref_ADDR=${var}_ADDR
        declare -n ref_SECRET=${var}_SECRET

        echo -e "\nclient $ref {" >> /etc/freeradius/clients.conf
        echo "    ipaddr = $ref_ADDR" >> /etc/freeradius/clients.conf
        echo "    secret = $ref_SECRET" >> /etc/freeradius/clients.conf
        echo "}" >> /etc/freeradius/clients.conf
    fi
done

if [ "${SETUP_PROXY}" == "1" ]; then
    print_header "Setup FreeRADIUS: proxy.conf"

    [ -z "$DOMAIN" ] && echo "DOMAIN env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR1_IPADDR" ] && echo "EDUROAM_FLR1_IPADDR env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR1_SECRET" ] && echo "EDUROAM_FLR1_SECRET env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR2_IPADDR" ] && echo "EDUROAM_FLR2_IPADDR env variable not defined! Exiting..." && exit 1
    [ -z "$EDUROAM_FLR2_SECRET" ] && echo "EDUROAM_FLR2_SECRET env variable not defined! Exiting..." && exit 1

    cat > /etc/freeradius/proxy.conf << EOL
proxy server {
	default_fallback = no
}

## eduroam config
home_server eduroam_flr_server_1 {
	type = auth
	ipaddr = $EDUROAM_FLR1_IPADDR
	secret = $EDUROAM_FLR1_SECRET
	port = 1812
}

home_server eduroam_flr_server_2 {
	type = auth
	ipaddr = $EDUROAM_FLR2_IPADDR
	secret = $EDUROAM_FLR2_SECRET
	port = 1812
}

home_server_pool EDUROAM {
    type = fail-over
    home_server = eduroam_flr_server_1

	# Only uncomment if there are two FLRS
	home_server = eduroam_flr_server_2
}

realm LOCAL {
}

realm ${DOMAIN,,} {
  authhost = LOCAL
  accthost = LOCAL
}

# null realm - allow here so we don't proxy inner tunnel
realm NULL {
  authhost = LOCAL
  accthost = LOCAL
}

# setup eduroam as default realm
realm DEFAULT {
	auth_pool = EDUROAM
	accthost = LOCAL
	nostrip
}
EOL
fi

print_header 'Configuring FreeRADIUS: inner-tunnel'
# we support 3 options, google ldap, ad ldap, and pam
if [ "$AD_DOMAIN" ]; then
    cp /templates/pam/inner-tunnel /etc/freeradius/sites-enabled/inner-tunnel
elif [ "$LDAP_SERVER" == "ldaps://ldap.google.com:636/" ]; then
    cp /templates/google-ldap/inner_tunnel /etc/freeradius/sites-enabled/inner-tunnel
else
    cp /templates/ad-ldap/inner_tunnel /etc/freeradius/sites-enabled/inner-tunnel
fi

# ldap may be needed for either AD or Google
if [ "$LDAP_SERVER" ]; then
    print_header "Configuring FreeRADIUS: LDAP"
    
    if [ "$LDAP_SERVER" == "ldaps://ldap.google.com:636/" ]; then
        # use envsubst to replace variables in the template
        envsubst '$LDAP_BASE_DN,$LDAP_BIND_DN,$LDAP_BIND_PW'  < /templates/google-ldap/ldap_google > /etc/freeradius/mods-enabled/ldap
    else
        envsubst '$LDAP_SERVER,$LDAP_BASE_DN,$LDAP_BIND_DN,$LDAP_BIND_PW,$LDAP_FILTER' < /templates/ad-ldap/ldap_ad > /etc/freeradius/mods-enabled/ldap
    fi
fi


print_header 'Configuring FreeRADIUS: logfiles'

# make sure linelogs exist with appropriate permissions
touch /var/log/freeradius/linelog-access
touch /var/log/freeradius/linelog-accounting
chown freerad:freerad /var/log/freeradius/linelog-access
chown freerad:freerad /var/log/freeradius/linelog-accounting
chmod 664 /var/log/freeradius/linelog-access
chmod 664 /var/log/freeradius/linelog-accounting

echo --------------------------------------------------
echo 'Configuring FreeRADIUS: certificates'
echo --------------------------------------------------

# Handle the rest of the certificates
# First the array of files which need 640 permissions
FILES_640=( "ca.key" "server.key" "server.p12" "server.pem" "google-ldap.crt" "google-ldap.key" )
for i in "${FILES_640[@]}"
do
	if [ -f "/certs/$i" ]; then
	    cp /certs/$i /etc/raddb/certs/$i
	    chmod 640 /etc/raddb/certs/$i
	fi
done

# Now all files that need a 644 permission set
FILES_644=( "ca.pem" "server.crt" "server.csr" "dh" )
for i in "${FILES_644[@]}"
do
	if [ -f "/certs/$i" ]; then
	    cp /certs/$i /etc/raddb/certs/$i
	    chmod 644 /etc/raddb/certs/$i
	fi
done

: '
echo --------------------------------------------------
echo 'Unset ENV Vars'
echo --------------------------------------------------

unset AD_PASSWORD
unset FR_SHARED_SECRET
unset EDUROAM_CLIENT_SECRET
unset EDUROAM_FLR1_SECRET
unset EDUROAM_FLR2_SECRET
'

/docker-entrypoint.sh "$@"