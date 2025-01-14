ARG FREERADIUS_VERSION=3.2.6

# build eapol_test for testing purposes
FROM freeradius/freeradius-server:${FREERADIUS_VERSION}-alpine AS build
RUN apk add git gcc make openssl openssl-dev libc-dev talloc-dev pcre-dev libidn-dev krb5-dev samba-dev curl-dev json-c-dev openldap-dev unbound-dev linux-headers && \
    mkdir /build && cd /build && \
    git clone --depth 1 --no-single-branch https://github.com/FreeRADIUS/freeradius-server.git
# sed fixes error on alpine systems
RUN cd /build/freeradius-server/scripts/ci/ && \
    sed -i 's/cp -n/cp/g' eapol_test-build.sh && \
    ./eapol_test-build.sh

FROM freeradius/freeradius-server:${FREERADIUS_VERSION}-alpine

COPY --from=build /build/freeradius-server/scripts/ci/eapol_test/eapol_test /usr/local/bin/

# Install Dependencies
RUN apk add bash gettext krb5 libidn

#RUN apt-get update -y && \
#    apt-get install -y winbind krb5-user libpam-krb5 libnss-winbind libpam-winbind samba samba-dsdb-modules samba-vfs-modules

#RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Allow freerad to access winbind socket & Enable Status
#RUN usermod -aG winbindd_priv freerad && \
#    ln -s /etc/freeradius/sites-available/status /etc/freeradius/sites-enabled/status && \
#    echo "rest {}" > /etc/freeradius/mods-enabled/rest

# Config Console Logging
#COPY configs/radiusd.conf /etc/freeradius/radiusd.conf

#COPY configs/clients.conf /etc/freeradius/clients.conf
#COPY configs/proxy.conf /etc/freeradius/proxy.conf
#COPY configs/default /etc/freeradius/sites-enabled/default
#COPY configs/inner-tunnel /etc/freeradius/sites-enabled/inner-tunnel
#COPY configs/linelog /etc/freeradius/mods-enabled/linelog
#COPY configs/mschap /etc/freeradius/mods-enabled/mschap
#COPY dictionary-files/dictionary.fortinet /usr/share/freeradius/dictionary.fortinet
#COPY dictionary-files/dictionary.eduroam /etc/freeradius/dictionary
#COPY configs/smb.conf /etc/samba/smb.conf

COPY scripts/init.sh /usr/local/bin

RUN chmod +x /usr/local/bin/init.sh

ENTRYPOINT ["/usr/local/bin/init.sh"]

CMD ["freeradius"]