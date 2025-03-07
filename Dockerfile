ARG FREERADIUS_VERSION=3.2.7

FROM freeradius/freeradius-server:${FREERADIUS_VERSION} AS build

RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install build-essential git libssl-dev devscripts pkg-config libnl-3-dev libnl-genl-3-dev -y && \
    mkdir /build && cd /build && \
    git clone --depth 1 --no-single-branch https://github.com/FreeRADIUS/freeradius-server.git && \
    cd /build/freeradius-server/scripts/ci/ && \
    ./eapol_test-build.sh

# Get acme.sh
RUN git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /acme.sh

FROM freeradius/freeradius-server:${FREERADIUS_VERSION}

COPY --from=build /build/freeradius-server/scripts/ci/eapol_test/eapol_test /usr/local/bin/
COPY --from=build /acme.sh /acme.sh

# Install winbind Dependencies
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y krb5-user libpam-krb5 pamtester gettext supervisor socat && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#COPY configs/linelog /etc/freeradius/mods-enabled/linelog
#COPY dictionary-files/dictionary.fortinet /usr/share/freeradius/dictionary.fortinet
#COPY dictionary-files/dictionary.eduroam /etc/freeradius/dictionary

# Change defaults
# 1. Send logs to stdout by default
# 2. Set require_message_authenticator = true for localhost client
# 3. Enable status module
# 4. Enable rest module
# 5. Setup certificates in format server expects
RUN sed -i 's/auth = no/auth = yes/g' /etc/raddb/radiusd.conf && \
    sed -i 's/destination = files/destination = stdout/g' /etc/raddb/radiusd.conf && \
    ln -s /etc/freeradius/sites-available/status /etc/freeradius/sites-enabled/status && \
    ln -s /etc/freeradius/mods-available/cache_auth /etc/freeradius/mods-enabled/cache_auth && \
    echo "rest {}" > /etc/freeradius/mods-enabled/rest && \
    cat /etc/raddb/certs/server.crt /etc/raddb/certs/ca.pem > /etc/raddb/certs/fullchain.pem && \
    bash -c 'openssl rsa -in /etc/raddb/certs/server.key -out /etc/raddb/certs/server.key -passin file:<( echo -n "whatever" )' && \
    chown root:freerad /etc/raddb/certs/server.key

# Default Environment Variables
ENV LDAP_FILTER="(sAMAccountName=%{%{Stripped-User-Name}:-%{User-Name}})"
ENV SETUP_PROXY=0
ENV SETUP_CLIENTS=1
ENV POSTGRES_PORT=5432

# Copy configurations
COPY configs/default /etc/raddb/sites-enabled/
COPY configs/post-auth.unl /etc/raddb/
COPY configs/pam.conf /etc/raddb/mods-enabled/
COPY configs/eap.conf /etc/raddb/mods-enabled/eap
COPY configs/templates /templates

COPY scripts/init.sh /usr/local/bin
COPY scripts/cert-renew.sh /usr/local/bin
COPY scripts/supervisord.conf /etc/supervisor/supervisord.conf

RUN chmod +x /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/cert-renew.sh

ENTRYPOINT ["/usr/local/bin/init.sh"]
