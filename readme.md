# FreeRADIUS Container

This is a heavily opinionated FreeRADIUS container that takes environment variables to perform most of the configuration.

## Usage

This container is designed to support both Kerberos and LDAP authentication using TTLS-PAP. It also can optionally proxy requests to eduroam. To see how to do so, look at the docs or read the below Environment Variables section.

### Kerberos vs LDAP

In general, I'm going to go against FreeRADIUS's recommendation and say that Kerberos is probably a bad idea. Its quicker and easier to setup, but its also a lot more obtuse and harder to debug. For example, almost any time you have an error with Kerberos, PAM will return a generic "Permission denied" message. Whereas with LDAP, you can get a more specific error message at least saying the password is incorrect.

Caching is setup for LDAP, so while performance suffers for first time auth, subsequent authentication attempts are significantly faster.

## Variables

There are A LOT of variable options. I am listing them here, but for specific use cases, you should check out the documentation.

### FreeRADIUS

FreeRADIUS configuration variables. Domain is required. Clients are optional.

| Variable | Default | Description |
| --- | --- | ---|
| `DOMAIN` | - | Domain name for FreeRADIUS |
| `RAD_CLIENT_*` | - | FreeRADIUS Client Name (replace `*` with number) |
| `RAD_CLIENT_*_ADDR` | - | CIDR used for by client # |
| `RAD_CLIENT_*_SECRET` | - | Secret used by client # |

### Active Directory

Technically not for Active Directory, but used for setting up PAM / Kerberos.

| Variable | Default | Description |
| --- | --- | ---|
| `AD_DOMAIN` | - | Active Directory Domain |
| `AD_WORKGROUP` | - | Active Directory Workgroup |
| `AD_SERVER` | - | Active Directory Server |

### LDAP

Used to setup LDAP authentication. If `LDAP_SERVER` is set, all fields are required except `LDAP_FILTER`.

| Variable | Default | Description |
| --- | --- | ---|
| `LDAP_SERVER` | - | LDAP Server URI (ex: `ldaps://ldap.google.com:636`) |
| `LDAP_BASE_DN` | - | Base DN |
| `LDAP_BIND_DN` | - | Username used to access LDAP server |
| `LDAP_BIND_PW` | - | Password used to access LDAP server |
| `LDAP_FILTER` | `(sAMAccountName=%{%{Stripped-User-Name}:-%{User-Name}})` | LDAP User Filter |

### Proxy Configuration

Proxy configuration is used to proxy requests to eduroam. `DOMAIN` is definitely required.

| Variable | Default | Description |
| --- | --- | ---|
| `SETUP_PROXY` | 0 | Set to `1` to run through setup |
| `EDUROAM_FLR1_IPADDR` | - | Eduroam FLR1 IP Address |
| `EDUROAM_FLR1_SECRET` | - | Eduroam FLR1 Secret |
| `EDUROAM_FLR2_IPADDR` | - | Eduroam FLR2 IP Address |
| `EDUROAM_FLR2_SECRET` | - | Eduroam FLR2 Secret |

To add eduroam clients, follow the same pattern as the FreeRADIUS clients, except use `EDUROAM_CLIENT_*` instead.

### Other

| Variable | Default | Description |
| --- | --- | ---|
| `DEBUG` | FALSE | Enable debugging for init script |

## Custom Logic

Need some custom logic for you use case? No problem! Just use a volume mount to override the specific file you need. Here are some of the files you can override:

- `clients.conf`
- `ldap.conf`
- `post-auth.unl`

For example, if you need to simplify the `post-auth.unl` process to always assign a VLAN to `testuser`, you can create a file called `post-auth.unl` with the following content:

```unlang
post-auth {
  if (User-Name == "testuser") {
    update reply {
      Tunnel-Type = VLAN,
      Tunnel-Medium-Type = IEEE-802,
      Tunnel-Private-Group-ID = 100
    }
  }
}
```

Then you can mount that file into the container like so:

```yaml
services:
  freeradius:
    image: ghcr.io/nnnc-org/freeradius:latest
    volumes:
      - ./post-auth.unl:/etc/freeradius/post-auth.unl
```

## Debugging

### TTLS / PAP

Included in the container is a tool called `eapol_test` which can be used to test TTLS / PAP authentication. To use it, you can run the following command:

```bash
docker exec -it radius_container eapol_test -c /etc/freeradius/eapol_test.conf
```

For more information on how to use `eapol_test`, you can check out the [debian manpage](https://manpages.debian.org/testing/eapoltest/eapol_test.8.en.html).

### Kerberos

`pamtester` is a great tool for debugging PAM (which is how we are using kerberos in this image). To use it, you can run the following command:

```bash
docker exec -it radius_container pamtester radiusd testuser@REALM.ORG authenticate
```
