FROM osixia/openldap:1.5.0

COPY bootstrap/ldif/01-structure.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/01-structure.ldif
COPY fix/admin/admin-password-change.ldif /container/service/slapd/assets/config/admin/admin-password-change.ldif
COPY fix/replication/replication-disable.ldif /container/service/slapd/assets/config/replication/replication-disable.ldif