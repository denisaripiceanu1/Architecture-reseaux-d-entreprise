FROM osixia/openldap:1.5.0

COPY bootstrap/ldif/01-structure.ldif /tmp/01-structure.ldif
COPY fix/admin/admin-password-change.ldif /tmp/admin-password-change.ldif
COPY fix/replication/replication-disable.ldif /tmp/replication-disable.ldif

RUN mkdir -p /container/service/slapd/assets/config/bootstrap/ldif/custom \
	/container/service/slapd/assets/config/admin \
	/container/service/slapd/assets/config/replication && \
	cp /tmp/01-structure.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/01-structure.ldif && \
	cp /tmp/admin-password-change.ldif /container/service/slapd/assets/config/admin/admin-password-change.ldif && \
	cp /tmp/replication-disable.ldif /container/service/slapd/assets/config/replication/replication-disable.ldif